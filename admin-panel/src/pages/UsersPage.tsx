import { useState } from 'react'
import {
  collection, query, orderBy, limit, getDocs,
  where, doc, getDoc,
} from 'firebase/firestore'
import { useQuery } from '@tanstack/react-query'
import {
  Users, Search, Wifi, WifiOff, Crown,
  ChevronRight, X, TrendingUp,
  ShoppingBag, Activity, Phone,
} from 'lucide-react'
import { db } from '@/lib/firebase'
import { fmtDate, fmtRs, pnlColor, cn } from '@/lib/utils'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'

// ── Types ─────────────────────────────────────────────────────────────────────

interface UserDoc {
  uid:                string
  phone_number?:      string
  name?:              string | null
  email?:             string | null
  created_at?:        unknown
}

interface UserRow extends UserDoc {
  hasActiveSub:    boolean
  brokerConnected: boolean
  planIds:         string[]
}

interface UserDetail extends UserRow {
  strategies: StrategyRow[]
  orders:     OrderRow[]
  totalPnl:   number
}

interface StrategyRow {
  id:     string
  name?:  string
  symbol?: string
  status: string
  pnl?:   number
}

interface OrderRow {
  id:       string
  symbol:   string
  action:   string
  status:   string
  price:    number
  quantity: number
  placedAt: unknown
}

// ── Queries ───────────────────────────────────────────────────────────────────

async function fetchUsers(): Promise<UserRow[]> {
  const snap = await getDocs(
    query(collection(db, 'users'), orderBy('created_at', 'desc'), limit(200))
  )

  const rows: UserRow[] = []

  await Promise.all(snap.docs.map(async d => {
    const data = d.data() as UserDoc

    // Check active subscription
    const subSnap = await getDocs(
      query(
        collection(db, 'subscriptions'),
        where('user_id', '==', d.id),
        where('is_active', '==', true),
        limit(5),
      )
    )
    const activeSubs = subSnap.docs.filter(s => {
      const exp = (s.data().expiry_date as any)?.toDate?.()
      return exp ? exp > new Date() : true
    })

    // Check broker connection
    const brokerSnap = await getDoc(
      doc(db, 'users', d.id, 'broker_connections', 'angel_one')
    )
    const brokerConnected = brokerSnap.exists() && (brokerSnap.data()?.is_connected === true)

    rows.push({
      uid:             d.id,
      phone_number:    data.phone_number,
      name:            data.name,
      email:           data.email,
      created_at:      data.created_at,
      hasActiveSub:    activeSubs.length > 0,
      brokerConnected,
      planIds:         activeSubs.map(s => s.data().plan_id as string),
    })
  }))

  return rows
}

async function fetchUserDetail(uid: string): Promise<UserDetail | null> {
  const [userSnap, subSnap, brokerSnap, stratSnap, orderSnap] = await Promise.all([
    getDoc(doc(db, 'users', uid)),
    getDocs(query(collection(db, 'subscriptions'), where('user_id', '==', uid), where('is_active', '==', true))),
    getDoc(doc(db, 'users', uid, 'broker_connections', 'angel_one')),
    getDocs(query(collection(db, 'users', uid, 'strategies'), orderBy('created_at', 'desc'), limit(20))),
    getDocs(query(collection(db, 'orders'), where('user_id', '==', uid), orderBy('placed_at', 'desc'), limit(30))),
  ])

  if (!userSnap.exists()) return null

  const data      = userSnap.data() as UserDoc
  const activeSubs = subSnap.docs.filter(s => {
    const exp = (s.data().expiry_date as any)?.toDate?.()
    return exp ? exp > new Date() : true
  })

  const strategies: StrategyRow[] = stratSnap.docs.map(d => ({
    id:     d.id,
    name:   d.data().name as string | undefined,
    symbol: (d.data().stock as any)?.symbol,
    status: d.data().status as string,
    pnl:    d.data().realised_pnl_rs as number | undefined,
  }))

  const orders: OrderRow[] = orderSnap.docs.map(d => ({
    id:       d.id,
    symbol:   d.data().symbol as string,
    action:   d.data().action as string,
    status:   d.data().status as string,
    price:    d.data().price as number,
    quantity: d.data().quantity as number,
    placedAt: d.data().placed_at,
  }))

  const totalPnl = strategies.reduce((sum, s) => sum + (s.pnl ?? 0), 0)

  return {
    uid,
    phone_number:    data.phone_number,
    name:            data.name,
    email:           data.email,
    created_at:      data.created_at,
    hasActiveSub:    activeSubs.length > 0,
    brokerConnected: brokerSnap.exists() && brokerSnap.data()?.is_connected === true,
    planIds:         activeSubs.map(s => s.data().plan_id as string),
    strategies,
    orders,
    totalPnl,
  }
}

// ── User Detail Drawer ────────────────────────────────────────────────────────

function UserDrawer({ uid, onClose }: { uid: string; onClose: () => void }) {
  const { data, isLoading } = useQuery({
    queryKey: ['user_detail', uid],
    queryFn:  () => fetchUserDetail(uid),
  })

  const statusVariant = (s: string) => {
    if (s === 'in_position') return 'info'
    if (s === 'target_hit') return 'success'
    if (s === 'sl_hit' || s === 'stoploss_hit') return 'danger'
    if (s === 'watching') return 'warning'
    if (s === 'closed') return 'muted'
    return 'default'
  }

  return (
    <div className="fixed inset-0 z-50 flex justify-end bg-black/60" onClick={onClose}>
      <div
        className="flex h-full w-full max-w-xl flex-col overflow-y-auto border-l border-gray-800 bg-gray-900 shadow-2xl"
        onClick={e => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between border-b border-gray-800 px-6 py-4">
          <div>
            <p className="text-base font-bold text-white">
              {data?.name || data?.phone_number || uid}
            </p>
            <p className="text-xs text-gray-500">{data?.email || data?.phone_number}</p>
          </div>
          <button onClick={onClose} className="rounded-md p-1.5 text-gray-400 hover:text-white">
            <X className="h-5 w-5" />
          </button>
        </div>

        {isLoading ? (
          <div className="flex flex-1 items-center justify-center">
            <div className="h-7 w-7 animate-spin rounded-full border-4 border-indigo-500 border-t-transparent" />
          </div>
        ) : !data ? (
          <p className="p-6 text-sm text-gray-500">User not found.</p>
        ) : (
          <div className="space-y-6 p-6">

            {/* Stats strip */}
            <div className="grid grid-cols-3 gap-3">
              {[
                { label: 'Strategies', value: data.strategies.length, icon: Activity },
                { label: 'Orders',     value: data.orders.length,     icon: ShoppingBag },
                { label: 'Total P&L',  value: fmtRs(data.totalPnl),   icon: TrendingUp, color: pnlColor(data.totalPnl) },
              ].map(({ label, value, icon: Icon, color }) => (
                <div key={label} className="rounded-xl border border-gray-800 bg-gray-800/50 p-3 text-center">
                  <Icon className={cn('mx-auto mb-1 h-4 w-4', color ?? 'text-gray-400')} />
                  <p className={cn('text-sm font-bold', color ?? 'text-white')}>{value}</p>
                  <p className="text-[10px] text-gray-500">{label}</p>
                </div>
              ))}
            </div>

            {/* Meta */}
            <div className="rounded-xl border border-gray-800 bg-gray-800/40 p-4 space-y-2 text-sm">
              <Row label="UID"      value={data.uid} mono />
              <Row label="Phone"    value={data.phone_number ?? '—'} />
              <Row label="Joined"   value={fmtDate(data.created_at as Parameters<typeof fmtDate>[0])} />
              <Row label="Broker"   value={data.brokerConnected ? 'Connected' : 'Not connected'}
                   valueClass={data.brokerConnected ? 'text-emerald-400' : 'text-red-400'} />
              <Row label="Plans"    value={data.planIds.length ? data.planIds.join(', ') : 'None'} />
            </div>

            {/* Strategies */}
            <Section title={`Strategies (${data.strategies.length})`}>
              {data.strategies.length === 0
                ? <Empty text="No strategies" />
                : data.strategies.map(s => (
                  <div key={s.id} className="flex items-center justify-between rounded-lg border border-gray-800 px-3 py-2.5">
                    <div>
                      <p className="text-sm font-semibold text-white">{s.symbol ?? s.name ?? s.id.slice(0, 8)}</p>
                      <p className="text-[11px] text-gray-500">{s.name}</p>
                    </div>
                    <div className="flex items-center gap-2">
                      {s.pnl !== undefined && s.pnl !== 0 && (
                        <span className={cn('text-xs font-bold', pnlColor(s.pnl))}>{fmtRs(s.pnl)}</span>
                      )}
                      <Badge variant={statusVariant(s.status) as any}>{s.status}</Badge>
                    </div>
                  </div>
                ))
              }
            </Section>

            {/* Recent orders */}
            <Section title={`Recent Orders (${data.orders.length})`}>
              {data.orders.length === 0
                ? <Empty text="No orders" />
                : data.orders.slice(0, 10).map(o => (
                  <div key={o.id} className="flex items-center justify-between rounded-lg border border-gray-800 px-3 py-2.5">
                    <div>
                      <div className="flex items-center gap-1.5">
                        <span className="text-sm font-semibold text-white">{o.symbol}</span>
                        <span className={cn(
                          'rounded px-1.5 py-0.5 text-[9px] font-bold',
                          o.action === 'BUY' ? 'bg-emerald-600/15 text-emerald-400' : 'bg-red-600/15 text-red-400',
                        )}>{o.action}</span>
                      </div>
                      <p className="text-[11px] text-gray-500">
                        {o.quantity} × ₹{o.price} · {fmtDate(o.placedAt as Parameters<typeof fmtDate>[0])}
                      </p>
                    </div>
                    <Badge variant={
                      o.status === 'complete' ? 'success'
                      : o.status === 'rejected' || o.status === 'cancelled' ? 'danger'
                      : 'warning'
                    }>{o.status}</Badge>
                  </div>
                ))
              }
            </Section>
          </div>
        )}
      </div>
    </div>
  )
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function Row({ label, value, mono, valueClass }: { label: string; value: string; mono?: boolean; valueClass?: string }) {
  return (
    <div className="flex justify-between gap-4">
      <span className="text-gray-500">{label}</span>
      <span className={cn('text-right text-white', mono && 'font-mono text-xs', valueClass)}>{value}</span>
    </div>
  )
}

function Section({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div className="space-y-2">
      <p className="text-[11px] font-bold uppercase tracking-wider text-gray-500">{title}</p>
      <div className="space-y-1.5">{children}</div>
    </div>
  )
}

function Empty({ text }: { text: string }) {
  return <p className="rounded-lg border border-gray-800 px-3 py-4 text-center text-xs text-gray-600">{text}</p>
}

// ── Main page ─────────────────────────────────────────────────────────────────

export default function UsersPage() {
  const [search,     setSearch]     = useState('')
  const [filterSub,  setFilterSub]  = useState<'all' | 'active' | 'none'>('all')
  const [filterBrok, setFilterBrok] = useState<'all' | 'yes' | 'no'>('all')
  const [selected,   setSelected]   = useState<string | null>(null)

  const { data: users = [], isLoading, refetch } = useQuery({
    queryKey: ['users'],
    queryFn:  fetchUsers,
    staleTime: 5 * 60_000,
  })

  const filtered = users.filter(u => {
    const q = search.toLowerCase()
    const matchQ = !q
      || u.name?.toLowerCase().includes(q)
      || u.phone_number?.includes(q)
      || u.email?.toLowerCase().includes(q)
      || u.uid.includes(q)
    const matchSub = filterSub === 'all'
      || (filterSub === 'active' && u.hasActiveSub)
      || (filterSub === 'none'   && !u.hasActiveSub)
    const matchBrok = filterBrok === 'all'
      || (filterBrok === 'yes' && u.brokerConnected)
      || (filterBrok === 'no'  && !u.brokerConnected)
    return matchQ && matchSub && matchBrok
  })

  return (
    <div className="space-y-5">

      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-bold text-white">Users</h1>
          <p className="mt-0.5 text-xs text-gray-500">
            {users.length} total · {users.filter(u => u.hasActiveSub).length} subscribed ·{' '}
            {users.filter(u => u.brokerConnected).length} broker connected
          </p>
        </div>
        <Button variant="ghost" size="sm" onClick={() => refetch()} loading={isLoading}>
          Refresh
        </Button>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap gap-2">
        <div className="relative min-w-[220px]">
          <Search className="absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-gray-500" />
          <input value={search} onChange={e => setSearch(e.target.value)}
            placeholder="Name, phone, email, UID…"
            className="w-full rounded-lg border border-gray-700 bg-gray-800 py-2 pl-9 pr-3 text-sm text-white placeholder-gray-600 focus:outline-none focus:ring-2 focus:ring-indigo-500" />
        </div>
        <select value={filterSub} onChange={e => setFilterSub(e.target.value as any)}
          className="rounded-lg border border-gray-700 bg-gray-800 px-3 py-2 text-sm text-white focus:outline-none focus:ring-2 focus:ring-indigo-500">
          <option value="all">All Subscription</option>
          <option value="active">Active Sub</option>
          <option value="none">No Sub</option>
        </select>
        <select value={filterBrok} onChange={e => setFilterBrok(e.target.value as any)}
          className="rounded-lg border border-gray-700 bg-gray-800 px-3 py-2 text-sm text-white focus:outline-none focus:ring-2 focus:ring-indigo-500">
          <option value="all">All Broker</option>
          <option value="yes">Broker Connected</option>
          <option value="no">Not Connected</option>
        </select>
      </div>

      {/* Table */}
      <div className="overflow-hidden rounded-xl border border-gray-800 bg-gray-900">
        {isLoading ? (
          <div className="space-y-px">
            {Array.from({ length: 8 }).map((_, i) => (
              <div key={i} className="h-14 animate-pulse bg-gray-800/60" style={{ opacity: 1 - i * 0.1 }} />
            ))}
          </div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center gap-2 py-16 text-gray-600">
            <Users className="h-8 w-8" />
            <p className="text-sm">No users found</p>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-gray-800 text-left text-[11px] font-semibold uppercase tracking-wider text-gray-500">
                  <th className="px-4 py-3">User</th>
                  <th className="px-4 py-3">Phone</th>
                  <th className="px-4 py-3">Subscription</th>
                  <th className="px-4 py-3">Broker</th>
                  <th className="px-4 py-3">Joined</th>
                  <th className="px-4 py-3 text-right">Detail</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-800">
                {filtered.map(u => (
                  <tr key={u.uid} className="hover:bg-gray-800/40 transition-colors">
                    <td className="px-4 py-3">
                      <div className="flex items-center gap-3">
                        <div className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-indigo-600/20 text-xs font-bold text-indigo-400">
                          {(u.name || u.phone_number || 'U')[0].toUpperCase()}
                        </div>
                        <div>
                          <p className="font-semibold text-white">{u.name || '—'}</p>
                          <p className="text-[11px] text-gray-500 font-mono">{u.uid.slice(0, 12)}…</p>
                        </div>
                      </div>
                    </td>
                    <td className="px-4 py-3 text-gray-300">
                      <div className="flex items-center gap-1.5">
                        <Phone className="h-3 w-3 text-gray-500" />
                        {u.phone_number || u.email || '—'}
                      </div>
                    </td>
                    <td className="px-4 py-3">
                      {u.hasActiveSub ? (
                        <div className="flex flex-wrap gap-1">
                          {u.planIds.map(p => (
                            <Badge key={p} variant="success">
                              <Crown className="mr-1 h-2.5 w-2.5" />{p}
                            </Badge>
                          ))}
                        </div>
                      ) : (
                        <Badge variant="muted">No plan</Badge>
                      )}
                    </td>
                    <td className="px-4 py-3">
                      {u.brokerConnected
                        ? <div className="flex items-center gap-1.5 text-emerald-400"><Wifi className="h-3.5 w-3.5" /><span className="text-xs">Connected</span></div>
                        : <div className="flex items-center gap-1.5 text-gray-600"><WifiOff className="h-3.5 w-3.5" /><span className="text-xs">—</span></div>}
                    </td>
                    <td className="px-4 py-3 text-xs text-gray-500">{fmtDate(u.created_at as Parameters<typeof fmtDate>[0])}</td>
                    <td className="px-4 py-3 text-right">
                      <button onClick={() => setSelected(u.uid)}
                        className="inline-flex items-center gap-1 rounded-lg border border-gray-700 px-2.5 py-1.5 text-xs text-gray-400 hover:bg-gray-800 hover:text-white">
                        View <ChevronRight className="h-3.5 w-3.5" />
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {selected && <UserDrawer uid={selected} onClose={() => setSelected(null)} />}
    </div>
  )
}
