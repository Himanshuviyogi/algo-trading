import { useState, useEffect } from 'react'
import {
  collection, query, orderBy, limit, onSnapshot,
  where, type QueryConstraint,
} from 'firebase/firestore'
import { db } from '@/lib/firebase'
import { fmtDate, cn } from '@/lib/utils'
import { Search, Layers, AlertTriangle } from 'lucide-react'
import Badge from '@/components/ui/Badge'

// ── Types ─────────────────────────────────────────────────────────────────────

interface Order {
  id:               string
  user_id:          string
  symbol:           string
  exchange:         string
  action:           string
  order_type:       string
  quantity:         number
  price:            number
  angel_order_id?:  string | null
  status:           string
  rejection_reason?: string | null
  order_role?:      string
  placed_at:        unknown
  updated_at:       unknown
  strategy_id?:     string
}

// ── Real-time hook ────────────────────────────────────────────────────────────

function useOrders(filterStatus: string, filterAction: string, searchUid: string) {
  const [orders,  setOrders]  = useState<Order[]>([])
  const [loading, setLoading] = useState(true)
  const [error,   setError]   = useState<string | null>(null)

  useEffect(() => {
    setLoading(true)
    const constraints: QueryConstraint[] = [
      orderBy('placed_at', 'desc'),
      limit(200),
    ]
    if (filterStatus !== 'all') constraints.unshift(where('status', '==', filterStatus))

    const q = query(collection(db, 'orders'), ...constraints)

    const unsub = onSnapshot(q,
      snap => {
        let docs = snap.docs.map(d => ({ id: d.id, ...d.data() } as Order))
        if (filterAction !== 'all') docs = docs.filter(o => o.action === filterAction)
        if (searchUid.trim()) docs = docs.filter(o => o.user_id.includes(searchUid.trim()) || o.symbol.toUpperCase().includes(searchUid.trim().toUpperCase()))
        setOrders(docs)
        setLoading(false)
      },
      err => { setError(err.message); setLoading(false) },
    )
    return unsub
  }, [filterStatus, filterAction, searchUid])

  return { orders, loading, error }
}

// ── Status / role badge helpers ───────────────────────────────────────────────

function statusBadge(status: string) {
  const map: Record<string, 'success' | 'warning' | 'danger' | 'muted' | 'info'> = {
    complete:  'success',
    open:      'info',
    pending:   'warning',
    rejected:  'danger',
    cancelled: 'muted',
  }
  return <Badge variant={map[status] ?? 'muted'}>{status}</Badge>
}

function roleBadge(role?: string | null) {
  if (!role || role === 'entry') return null
  const map: Record<string, string> = {
    exit:           'bg-purple-600/15 text-purple-400',
    bracket_sl:     'bg-red-600/15 text-red-400',
    bracket_target: 'bg-emerald-600/15 text-emerald-400',
  }
  return (
    <span className={cn('rounded-full px-2 py-0.5 text-[9px] font-bold uppercase', map[role] ?? 'bg-gray-700 text-gray-400')}>
      {role.replace('_', ' ')}
    </span>
  )
}

// ── Page ──────────────────────────────────────────────────────────────────────

const STATUS_OPTIONS = ['all', 'complete', 'open', 'pending', 'rejected', 'cancelled']
const ACTION_OPTIONS = ['all', 'BUY', 'SELL']

export default function OrdersPage() {
  const [filterStatus, setFilterStatus] = useState('all')
  const [filterAction, setFilterAction] = useState('all')
  const [search,       setSearch]       = useState('')

  const { orders, loading, error } = useOrders(filterStatus, filterAction, search)

  const counts = {
    complete:  orders.filter(o => o.status === 'complete').length,
    active:    orders.filter(o => o.status === 'open' || o.status === 'pending').length,
    rejected:  orders.filter(o => o.status === 'rejected' || o.status === 'cancelled').length,
  }

  return (
    <div className="space-y-5">

      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-bold text-white">Orders</h1>
          <p className="mt-0.5 text-xs text-gray-500">
            {orders.length} shown · {counts.active} active · {counts.complete} complete · {counts.rejected} rejected/cancelled
          </p>
        </div>
        <div className="flex items-center gap-1.5 rounded-lg border border-emerald-800 bg-emerald-950/30 px-3 py-1.5">
          <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-emerald-400" />
          <span className="text-[11px] font-semibold text-emerald-400">Live stream</span>
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
          {STATUS_OPTIONS.map(s => <option key={s} value={s}>{s === 'all' ? 'All Status' : s}</option>)}
        </select>

        <select value={filterAction} onChange={e => setFilterAction(e.target.value)}
          className="rounded-lg border border-gray-700 bg-gray-800 px-3 py-2 text-sm text-white focus:outline-none focus:ring-2 focus:ring-indigo-500">
          {ACTION_OPTIONS.map(a => <option key={a} value={a}>{a === 'all' ? 'All Actions' : a}</option>)}
        </select>
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
            {Array.from({ length: 8 }).map((_, i) => (
              <div key={i} className="h-14 animate-pulse bg-gray-800/60" style={{ opacity: 1 - i * 0.1 }} />
            ))}
          </div>
        ) : orders.length === 0 ? (
          <div className="flex flex-col items-center gap-2 py-16 text-gray-600">
            <Layers className="h-8 w-8" />
            <p className="text-sm">No orders match your filters</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-gray-800 text-left text-[11px] font-semibold uppercase tracking-wider text-gray-500">
                  <th className="px-4 py-3">Symbol</th>
                  <th className="px-4 py-3">User</th>
                  <th className="px-4 py-3">Action</th>
                  <th className="px-4 py-3">Qty × Price</th>
                  <th className="px-4 py-3">Type</th>
                  <th className="px-4 py-3">Angel ID</th>
                  <th className="px-4 py-3">Status</th>
                  <th className="px-4 py-3">Placed</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-800">
                {orders.map(o => (
                  <tr key={o.id} className="hover:bg-gray-800/40 transition-colors">
                    <td className="px-4 py-3">
                      <div>
                        <span className="font-semibold text-white">{o.symbol}</span>
                        <span className="ml-1.5 text-[10px] text-gray-600">{o.exchange}</span>
                      </div>
                      {roleBadge(o.order_role)}
                    </td>
                    <td className="px-4 py-3">
                      <span className="font-mono text-xs text-gray-400">{o.user_id?.slice(0, 12)}…</span>
                    </td>
                    <td className="px-4 py-3">
                      <span className={cn(
                        'rounded px-2 py-0.5 text-xs font-bold',
                        o.action === 'BUY' ? 'bg-emerald-600/15 text-emerald-400' : 'bg-red-600/15 text-red-400',
                      )}>
                        {o.action}
                      </span>
                    </td>
                    <td className="px-4 py-3 text-gray-200">
                      {o.quantity} × ₹{o.price?.toFixed(2)}
                    </td>
                    <td className="px-4 py-3 text-xs text-gray-500">{o.order_type}</td>
                    <td className="px-4 py-3">
                      {o.angel_order_id
                        ? <span className="font-mono text-xs text-indigo-400">{o.angel_order_id}</span>
                        : <span className="text-xs text-gray-700">—</span>}
                    </td>
                    <td className="px-4 py-3">
                      <div className="space-y-1">
                        {statusBadge(o.status)}
                        {o.rejection_reason && (
                          <p className="text-[10px] text-red-400 max-w-[180px] truncate" title={o.rejection_reason}>
                            {o.rejection_reason}
                          </p>
                        )}
                      </div>
                    </td>
                    <td className="px-4 py-3 text-xs text-gray-500 whitespace-nowrap">
                      {fmtDate(o.placed_at as Parameters<typeof fmtDate>[0])}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>
    </div>
  )
}
