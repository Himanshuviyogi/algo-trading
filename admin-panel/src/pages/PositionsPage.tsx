import { useState, useEffect } from 'react'
import {
  collection, query, orderBy, limit,
  onSnapshot, where,
} from 'firebase/firestore'
import { useMutation } from '@tanstack/react-query'
import axios from 'axios'
import { TrendingUp, TrendingDown, X, AlertTriangle, Search } from 'lucide-react'
import { db } from '@/lib/firebase'
import { fmtDate, fmtRs, pnlColor, cn } from '@/lib/utils'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'

// ── Types ─────────────────────────────────────────────────────────────────────

interface Position {
  id:          string
  user_id:     string
  symbol:      string
  exchange:    string
  action:      string
  quantity:    number
  avg_price:   number
  current_price: number
  pnl:         number
  pnl_percent: number
  status:      string
  opened_at:   unknown
  closed_at?:  unknown
  signal_id?:  string
  order_id?:   string
  strategy_id?: string
}

// ── Real-time hook ────────────────────────────────────────────────────────────

function usePositions(filterStatus: string, search: string) {
  const [positions, setPositions] = useState<Position[]>([])
  const [loading,   setLoading]   = useState(true)
  const [error,     setError]     = useState<string | null>(null)

  useEffect(() => {
    setLoading(true)
    const q = filterStatus === 'all'
      ? query(collection(db, 'positions'), orderBy('opened_at', 'desc'), limit(200))
      : query(collection(db, 'positions'), where('status', '==', filterStatus), orderBy('opened_at', 'desc'), limit(200))

    const unsub = onSnapshot(q,
      snap => {
        let docs = snap.docs.map(d => ({ id: d.id, ...d.data() } as Position))
        if (search.trim()) {
          const q = search.trim().toUpperCase()
          docs = docs.filter(p => p.symbol.includes(q) || p.user_id.includes(search.trim()))
        }
        setPositions(docs)
        setLoading(false)
      },
      err => { setError(err.message); setLoading(false) },
    )
    return unsub
  }, [filterStatus, search])

  return { positions, loading, error }
}

// ── Force-close confirm modal ─────────────────────────────────────────────────

const PRICE_SERVER = import.meta.env.VITE_PRICE_SERVER_URL ?? '/api/price-server'

function CloseConfirm({ position, onClose }: { position: Position; onClose: () => void }) {
  const close = useMutation({
    mutationFn: () =>
      axios.post(`${PRICE_SERVER}/close-position`, {
        positionId: position.id,
        userId:     position.user_id,
      }),
    onSuccess: onClose,
  })

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4">
      <div className="w-full max-w-sm rounded-2xl border border-gray-800 bg-gray-900 p-6 shadow-2xl">
        <div className="mb-4 flex h-11 w-11 items-center justify-center rounded-xl bg-red-600/15">
          <X className="h-5 w-5 text-red-400" />
        </div>
        <h3 className="text-base font-bold text-white">Force-close position?</h3>
        <p className="mt-1 text-sm text-gray-400">
          This will place a <strong className="text-white">MARKET {position.action === 'BUY' ? 'SELL' : 'BUY'}</strong> order
          for <strong className="text-white">{position.quantity} × {position.symbol}</strong> on behalf of user{' '}
          <span className="font-mono text-xs">{position.user_id.slice(0, 12)}…</span>
        </p>
        <p className="mt-2 text-xs text-amber-400">
          Current P&L: <span className="font-bold">{fmtRs(position.pnl)}</span>
        </p>

        {close.isError && (
          <div className="mt-3 flex items-center gap-2 rounded-lg border border-red-800 bg-red-950 px-3 py-2 text-xs text-red-300">
            <AlertTriangle className="h-3.5 w-3.5 shrink-0" />
            {(close.error as Error)?.message ?? 'Failed to close position'}
          </div>
        )}

        <div className="mt-5 flex gap-3">
          <Button variant="ghost" className="flex-1" onClick={onClose}>Cancel</Button>
          <Button variant="danger" className="flex-1" loading={close.isPending}
            onClick={() => close.mutate()}>
            Force Close
          </Button>
        </div>
      </div>
    </div>
  )
}

// ── Page ──────────────────────────────────────────────────────────────────────

export default function PositionsPage() {
  const [filterStatus, setFilterStatus] = useState('open')
  const [search,       setSearch]       = useState('')
  const [closing,      setClosing]      = useState<Position | null>(null)

  const { positions, loading, error } = usePositions(filterStatus, search)

  const openPositions = positions.filter(p => p.status === 'open')

  // Aggregate stats
  const totalPnl      = openPositions.reduce((s, p) => s + (p.pnl ?? 0), 0)
  const totalExposure = openPositions.reduce((s, p) => s + (p.avg_price * p.quantity), 0)

  return (
    <div className="space-y-5">

      {/* Header */}
      <div className="flex flex-wrap items-start justify-between gap-3">
        <div>
          <h1 className="text-xl font-bold text-white">Positions</h1>
          <p className="mt-0.5 text-xs text-gray-500">
            {positions.length} shown · {openPositions.length} open
          </p>
        </div>

        {/* Summary strip */}
        <div className="flex gap-3">
          <div className="rounded-xl border border-gray-800 bg-gray-900 px-4 py-2.5">
            <p className="text-[10px] text-gray-500">Open P&L</p>
            <p className={cn('text-base font-bold', pnlColor(totalPnl))}>{fmtRs(totalPnl)}</p>
          </div>
          <div className="rounded-xl border border-gray-800 bg-gray-900 px-4 py-2.5">
            <p className="text-[10px] text-gray-500">Exposure</p>
            <p className="text-base font-bold text-white">{fmtRs(totalExposure)}</p>
          </div>
        </div>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap gap-2">
        <div className="relative min-w-[220px]">
          <Search className="absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-gray-500" />
          <input value={search} onChange={e => setSearch(e.target.value)}
            placeholder="Symbol or user UID…"
            className="w-full rounded-lg border border-gray-700 bg-gray-800 py-2 pl-9 pr-3 text-sm text-white placeholder-gray-600 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
        </div>

        <select value={filterStatus} onChange={e => setFilterStatus(e.target.value)}
          className="rounded-lg border border-gray-700 bg-gray-800 px-3 py-2 text-sm text-white focus:outline-none focus:ring-2 focus:ring-indigo-500">
          <option value="all">All Status</option>
          <option value="open">Open</option>
          <option value="closed">Closed</option>
        </select>

        <div className="flex items-center gap-1.5 rounded-lg border border-emerald-800 bg-emerald-950/30 px-3 py-1.5 ml-auto">
          <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-emerald-400" />
          <span className="text-[11px] font-semibold text-emerald-400">Live stream</span>
        </div>
      </div>

      {/* Error */}
      {error && (
        <div className="flex items-center gap-2 rounded-lg border border-red-800 bg-red-950 px-4 py-3 text-sm text-red-300">
          <AlertTriangle className="h-4 w-4 shrink-0" /> {error}
        </div>
      )}

      {/* Table */}
      <div className="overflow-hidden rounded-xl border border-gray-800 bg-gray-900">
        {loading ? (
          <div className="space-y-px">
            {Array.from({ length: 6 }).map((_, i) => (
              <div key={i} className="h-14 animate-pulse bg-gray-800/60" style={{ opacity: 1 - i * 0.12 }} />
            ))}
          </div>
        ) : positions.length === 0 ? (
          <div className="flex flex-col items-center gap-2 py-16 text-gray-600">
            <TrendingUp className="h-8 w-8" />
            <p className="text-sm">No positions</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-gray-800 text-left text-[11px] font-semibold uppercase tracking-wider text-gray-500">
                  <th className="px-4 py-3">Symbol</th>
                  <th className="px-4 py-3">User</th>
                  <th className="px-4 py-3">Side</th>
                  <th className="px-4 py-3">Qty</th>
                  <th className="px-4 py-3">Avg Price</th>
                  <th className="px-4 py-3">P&L</th>
                  <th className="px-4 py-3">Status</th>
                  <th className="px-4 py-3">Opened</th>
                  <th className="px-4 py-3 text-right">Action</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-800">
                {positions.map(p => {
                  const isProfit  = p.pnl >= 0
                  const isOpen    = p.status === 'open'
                  return (
                    <tr key={p.id} className="hover:bg-gray-800/40 transition-colors">
                      <td className="px-4 py-3">
                        <div>
                          <span className="font-semibold text-white">{p.symbol}</span>
                          <span className="ml-1.5 text-[10px] text-gray-600">{p.exchange}</span>
                        </div>
                      </td>
                      <td className="px-4 py-3">
                        <span className="font-mono text-xs text-gray-400">{p.user_id?.slice(0, 12)}…</span>
                      </td>
                      <td className="px-4 py-3">
                        <span className={cn(
                          'rounded px-2 py-0.5 text-xs font-bold',
                          p.action === 'BUY' ? 'bg-emerald-600/15 text-emerald-400' : 'bg-red-600/15 text-red-400',
                        )}>
                          {p.action}
                        </span>
                      </td>
                      <td className="px-4 py-3 text-gray-300">{p.quantity}</td>
                      <td className="px-4 py-3 text-gray-300">₹{p.avg_price?.toFixed(2)}</td>
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-1.5">
                          {isProfit
                            ? <TrendingUp className="h-3.5 w-3.5 text-emerald-400" />
                            : <TrendingDown className="h-3.5 w-3.5 text-red-400" />}
                          <span className={cn('font-bold', pnlColor(p.pnl))}>
                            {fmtRs(p.pnl)}
                          </span>
                          <span className={cn('text-[11px]', pnlColor(p.pnl_percent))}>
                            ({p.pnl_percent >= 0 ? '+' : ''}{p.pnl_percent?.toFixed(2)}%)
                          </span>
                        </div>
                      </td>
                      <td className="px-4 py-3">
                        <Badge variant={isOpen ? 'info' : 'muted'}>{p.status}</Badge>
                      </td>
                      <td className="px-4 py-3 text-xs text-gray-500 whitespace-nowrap">
                        {fmtDate(p.opened_at as Parameters<typeof fmtDate>[0])}
                      </td>
                      <td className="px-4 py-3 text-right">
                        {isOpen && (
                          <Button size="sm" variant="danger"
                            onClick={() => setClosing(p)}>
                            Force Close
                          </Button>
                        )}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {closing && (
        <CloseConfirm position={closing} onClose={() => setClosing(null)} />
      )}
    </div>
  )
}
