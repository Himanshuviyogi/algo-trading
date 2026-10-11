import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { doc, getDoc, setDoc } from 'firebase/firestore'
import {
  TrendingUp, TrendingDown, Activity, Bot,
  Wifi, WifiOff, RefreshCw, Power, PowerOff,
  BarChart2, AlertTriangle, CheckCircle2,
} from 'lucide-react'
import { db } from '@/lib/firebase'
import { fetchHealth, startBroker, stopBroker, reloadSymbols } from '@/lib/priceServer'
import { fmtRs, fmtDate, cn } from '@/lib/utils'
import StatCard from '@/components/ui/StatCard'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import {
  LineChart, Line, XAxis, YAxis, Tooltip,
  ResponsiveContainer, CartesianGrid,
} from 'recharts'

// ── Types ─────────────────────────────────────────────────────────────────────

interface AlgoStats {
  deployed_strategies: number
  active_bots:         number
  watching_bots:       number
  today_pnl:           number
  overall_pnl:         number
  total_trades_today:  number
  win_rate_today:      number
  updated_at?:         { toDate?: () => Date } | null
}

interface AlgoRisk {
  algo_enabled:        boolean
  max_open_positions:  number
  max_order_value:     number
  daily_loss_limit:    number
  total_capital:       number
}

// ── Data hooks ────────────────────────────────────────────────────────────────

function useAlgoStats() {
  return useQuery<AlgoStats>({
    queryKey: ['algo_stats'],
    queryFn:  async () => {
      const snap = await getDoc(doc(db, 'app_config', 'algo_stats'))
      if (!snap.exists()) return {
        deployed_strategies: 0, active_bots: 0, watching_bots: 0,
        today_pnl: 0, overall_pnl: 0, total_trades_today: 0, win_rate_today: 0,
      }
      return snap.data() as AlgoStats
    },
    refetchInterval: 60_000,  // auto-refresh every 60 s
  })
}

function useAlgoRisk() {
  return useQuery<AlgoRisk>({
    queryKey: ['algo_risk'],
    queryFn:  async () => {
      const snap = await getDoc(doc(db, 'app_config', 'algo_risk'))
      return (snap.data() ?? {
        algo_enabled: false, max_open_positions: 5,
        max_order_value: 50_000, daily_loss_limit: 3_000, total_capital: 1_00_000,
      }) as AlgoRisk
    },
  })
}

function usePriceServerHealth() {
  return useQuery({
    queryKey: ['health'],
    queryFn:  fetchHealth,
    refetchInterval: 30_000,
    retry: 1,
  })
}

// ── Page ──────────────────────────────────────────────────────────────────────

export default function DashboardPage() {
  const qc          = useQueryClient()
  const stats       = useAlgoStats()
  const risk        = useAlgoRisk()
  const health      = usePriceServerHealth()

  const s = stats.data
  const r = risk.data
  const h = health.data

  // ── Mutations ───────────────────────────────────────────────────────────────

  const toggleAlgo = useMutation({
    mutationFn: async (enabled: boolean) => {
      await setDoc(doc(db, 'app_config', 'algo_risk'), { algo_enabled: enabled }, { merge: true })
    },
    onSuccess: () => qc.invalidateQueries({ queryKey: ['algo_risk'] }),
  })

  const brokerStart = useMutation({
    mutationFn: startBroker,
    onSuccess:  () => qc.invalidateQueries({ queryKey: ['health'] }),
  })

  const brokerStop = useMutation({
    mutationFn: stopBroker,
    onSuccess:  () => qc.invalidateQueries({ queryKey: ['health'] }),
  })

  const reloadSym = useMutation({ mutationFn: reloadSymbols })

  // ── Helpers ─────────────────────────────────────────────────────────────────

  const brokerOnline  = h?.broker === 'connected'
  const serverReach   = health.isSuccess
  const algoEnabled   = r?.algo_enabled ?? false

  const refreshAll = () => {
    qc.invalidateQueries({ queryKey: ['algo_stats'] })
    qc.invalidateQueries({ queryKey: ['algo_risk'] })
    qc.invalidateQueries({ queryKey: ['health'] })
  }

  // Mock equity curve from overall_pnl (replace with real time-series when available)
  const equitySpark = s ? (() => {
    const base = s.overall_pnl
    return Array.from({ length: 8 }, (_, i) => ({
      t:   `D-${7 - i}`,
      pnl: +(base * (0.75 + i * 0.035 + Math.sin(i) * 0.05)).toFixed(0),
    }))
  })() : []

  return (
    <div className="space-y-6">

      {/* ── Page header ─────────────────────────────────────────────────── */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-bold text-white">Dashboard</h1>
          <p className="mt-0.5 text-xs text-gray-500">
            Last updated: {fmtDate(s?.updated_at)}
          </p>
        </div>
        <Button variant="ghost" size="sm" icon={RefreshCw} onClick={refreshAll}
          loading={stats.isFetching}>
          Refresh
        </Button>
      </div>

      {/* ── Status strip ────────────────────────────────────────────────── */}
      <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">

        {/* Algo engine toggle */}
        <div className="col-span-2 flex items-center justify-between rounded-xl border border-gray-800 bg-gray-900 p-4 sm:col-span-1">
          <div>
            <p className="text-[10px] font-bold uppercase tracking-wider text-gray-500">Algo Engine</p>
            <p className={cn('mt-1 text-sm font-bold', algoEnabled ? 'text-emerald-400' : 'text-red-400')}>
              {algoEnabled ? 'Running' : 'Stopped'}
            </p>
          </div>
          <button
            onClick={() => toggleAlgo.mutate(!algoEnabled)}
            disabled={toggleAlgo.isPending || risk.isLoading}
            className={cn(
              'relative inline-flex h-6 w-11 items-center rounded-full transition-colors',
              'focus:outline-none focus:ring-2 focus:ring-indigo-500',
              'disabled:opacity-50',
              algoEnabled ? 'bg-emerald-600' : 'bg-gray-700',
            )}
          >
            <span className={cn(
              'inline-block h-4 w-4 rounded-full bg-white shadow transition-transform',
              algoEnabled ? 'translate-x-6' : 'translate-x-1',
            )} />
          </button>
        </div>

        {/* Price server health */}
        <div className="flex items-center justify-between rounded-xl border border-gray-800 bg-gray-900 p-4">
          <div>
            <p className="text-[10px] font-bold uppercase tracking-wider text-gray-500">Price Server</p>
            <p className={cn('mt-1 text-sm font-bold', serverReach ? 'text-emerald-400' : 'text-red-400')}>
              {health.isLoading ? 'Checking…' : serverReach ? 'Reachable' : 'Unreachable'}
            </p>
          </div>
          {serverReach
            ? <Wifi className="h-5 w-5 text-emerald-400" />
            : <WifiOff className="h-5 w-5 text-red-400" />}
        </div>

        {/* Broker WebSocket */}
        <div className="flex items-center justify-between rounded-xl border border-gray-800 bg-gray-900 p-4">
          <div>
            <p className="text-[10px] font-bold uppercase tracking-wider text-gray-500">Broker Feed</p>
            <p className={cn('mt-1 text-sm font-bold', brokerOnline ? 'text-emerald-400' : 'text-amber-400')}>
              {health.isLoading ? '—' : brokerOnline ? 'Live' : 'Offline'}
            </p>
          </div>
          <Badge variant={brokerOnline ? 'success' : 'warning'}>
            {brokerOnline ? 'LIVE' : 'OFF'}
          </Badge>
        </div>

        {/* Cached symbols */}
        <div className="flex items-center justify-between rounded-xl border border-gray-800 bg-gray-900 p-4">
          <div>
            <p className="text-[10px] font-bold uppercase tracking-wider text-gray-500">Symbols Cached</p>
            <p className="mt-1 text-sm font-bold text-white">
              {h?.cachedSymbols ?? '—'}
            </p>
          </div>
          <BarChart2 className="h-5 w-5 text-gray-500" />
        </div>
      </div>

      {/* ── Key metrics grid ─────────────────────────────────────────────── */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        <StatCard
          label="Deployed Strategies"
          value={s?.deployed_strategies ?? 0}
          icon={Activity}
          iconColor="text-indigo-400"
          iconBg="bg-indigo-600/15"
          loading={stats.isLoading}
        />
        <StatCard
          label="Active Positions"
          value={s?.active_bots ?? 0}
          sub={`${s?.watching_bots ?? 0} watching`}
          icon={Bot}
          iconColor="text-emerald-400"
          iconBg="bg-emerald-600/15"
          loading={stats.isLoading}
        />
        <StatCard
          label="Today's P&L"
          value={s ? fmtRs(s.today_pnl) : '—'}
          sub={`${s?.total_trades_today ?? 0} trades · ${s?.win_rate_today ?? 0}% win rate`}
          icon={s?.today_pnl !== undefined && s.today_pnl >= 0 ? TrendingUp : TrendingDown}
          iconColor={s?.today_pnl !== undefined && s.today_pnl >= 0 ? 'text-emerald-400' : 'text-red-400'}
          iconBg={s?.today_pnl !== undefined && s.today_pnl >= 0 ? 'bg-emerald-600/15' : 'bg-red-600/15'}
          loading={stats.isLoading}
        />
        <StatCard
          label="Overall P&L"
          value={s ? fmtRs(s.overall_pnl) : '—'}
          icon={TrendingUp}
          iconColor="text-sky-400"
          iconBg="bg-sky-600/15"
          loading={stats.isLoading}
        />
      </div>

      {/* ── Charts + controls row ────────────────────────────────────────── */}
      <div className="grid gap-4 lg:grid-cols-3">

        {/* Equity curve sparkline */}
        <div className="col-span-2 rounded-xl border border-gray-800 bg-gray-900 p-5">
          <p className="mb-4 text-xs font-bold uppercase tracking-wider text-gray-500">
            Overall P&L trend (indicative)
          </p>
          {stats.isLoading ? (
            <div className="h-40 animate-pulse rounded-lg bg-gray-800" />
          ) : (
            <ResponsiveContainer width="100%" height={160}>
              <LineChart data={equitySpark}>
                <CartesianGrid stroke="#1f2937" strokeDasharray="3 3" />
                <XAxis dataKey="t" tick={{ fill: '#6b7280', fontSize: 11 }} axisLine={false} tickLine={false} />
                <YAxis tick={{ fill: '#6b7280', fontSize: 11 }} axisLine={false} tickLine={false}
                  tickFormatter={(v: number) => fmtRs(v)} />
                <Tooltip
                  contentStyle={{ background: '#111827', border: '1px solid #374151', borderRadius: 8 }}
                  labelStyle={{ color: '#9ca3af', fontSize: 11 }}
                  formatter={(v: number) => [fmtRs(v), 'P&L']}
                />
                <Line type="monotone" dataKey="pnl" stroke="#6366f1"
                  strokeWidth={2} dot={false} activeDot={{ r: 4 }} />
              </LineChart>
            </ResponsiveContainer>
          )}
        </div>

        {/* Price server controls */}
        <div className="rounded-xl border border-gray-800 bg-gray-900 p-5 space-y-4">
          <p className="text-xs font-bold uppercase tracking-wider text-gray-500">
            Server Controls
          </p>

          {/* Uptime */}
          {h && (
            <div className="rounded-lg bg-gray-800 px-3 py-2.5 text-xs space-y-1">
              <div className="flex justify-between text-gray-400">
                <span>Uptime</span>
                <span className="text-white font-semibold">
                  {Math.floor((h.uptime ?? 0) / 3600)}h {Math.floor(((h.uptime ?? 0) % 3600) / 60)}m
                </span>
              </div>
              <div className="flex justify-between text-gray-400">
                <span>Status</span>
                <span className="text-emerald-400 font-semibold">{h.status}</span>
              </div>
            </div>
          )}

          <div className="space-y-2">
            <Button
              variant={brokerOnline ? 'danger' : 'primary'}
              size="sm"
              icon={brokerOnline ? PowerOff : Power}
              loading={brokerStart.isPending || brokerStop.isPending}
              onClick={() => brokerOnline ? brokerStop.mutate() : brokerStart.mutate()}
              className="w-full justify-center"
            >
              {brokerOnline ? 'Stop Broker Feed' : 'Start Broker Feed'}
            </Button>

            <Button
              variant="outline"
              size="sm"
              icon={RefreshCw}
              loading={reloadSym.isPending}
              onClick={() => reloadSym.mutate()}
              className="w-full justify-center"
            >
              Reload Symbols
            </Button>
          </div>

          {reloadSym.isSuccess && (
            <div className="flex items-center gap-1.5 text-xs text-emerald-400">
              <CheckCircle2 className="h-3.5 w-3.5" />
              {(reloadSym.data as { count?: number })?.count ?? 0} symbols reloaded
            </div>
          )}

          {(brokerStart.isError || brokerStop.isError) && (
            <div className="flex items-center gap-1.5 text-xs text-red-400">
              <AlertTriangle className="h-3.5 w-3.5" />
              Action failed — check server logs
            </div>
          )}
        </div>
      </div>

      {/* ── Risk config summary ──────────────────────────────────────────── */}
      <div className="rounded-xl border border-gray-800 bg-gray-900 p-5">
        <div className="mb-4 flex items-center justify-between">
          <p className="text-xs font-bold uppercase tracking-wider text-gray-500">
            Risk Config <span className="text-gray-700">(app_config/algo_risk)</span>
          </p>
          <Badge variant="muted">Read-only in Phase 1</Badge>
        </div>
        {risk.isLoading ? (
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            {Array.from({ length: 4 }).map((_, i) => (
              <div key={i} className="h-12 animate-pulse rounded-lg bg-gray-800" />
            ))}
          </div>
        ) : (
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            {[
              { label: 'Total Capital',      value: fmtRs(r?.total_capital ?? 0) },
              { label: 'Max Positions',      value: r?.max_open_positions ?? 0 },
              { label: 'Max Order Value',    value: fmtRs(r?.max_order_value ?? 0) },
              { label: 'Daily Loss Limit',   value: fmtRs(r?.daily_loss_limit ?? 0) },
            ].map(({ label, value }) => (
              <div key={label} className="rounded-lg bg-gray-800 px-3 py-2.5">
                <p className="text-[10px] text-gray-500">{label}</p>
                <p className="mt-1 text-sm font-bold text-white">{value}</p>
              </div>
            ))}
          </div>
        )}
        <p className="mt-3 text-[11px] text-gray-600">
          Edit these values in <strong className="text-gray-500">Risk Controls</strong> (Phase 2) or directly in Firebase Console → app_config/algo_risk.
        </p>
      </div>

    </div>
  )
}
