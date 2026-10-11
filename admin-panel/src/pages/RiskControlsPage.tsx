import { useState } from 'react'
import { doc, getDoc, setDoc, serverTimestamp } from 'firebase/firestore'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import {
  ShieldCheck, Save, AlertTriangle, CheckCircle2,
  Info, FlaskConical,
} from 'lucide-react'
import { db } from '@/lib/firebase'
import { fmtDate, cn } from '@/lib/utils'
import Button from '@/components/ui/Button'
import Badge from '@/components/ui/Badge'

// ── Types ─────────────────────────────────────────────────────────────────────

interface AlgoRisk {
  algo_enabled:          boolean
  max_open_positions:    number
  max_order_value:       number
  daily_loss_limit:      number
  daily_loss_limit_pct:  number
  total_capital:         number
  position_size_pct:     number
  paper_trading:         boolean
  updated_at?:           unknown
}

// ── Schema ────────────────────────────────────────────────────────────────────

const schema = z.object({
  algo_enabled:         z.boolean(),
  paper_trading:        z.boolean(),
  total_capital:        z.number().min(1000,   'Minimum ₹1,000'),
  position_size_pct:    z.number().min(0.5).max(50, 'Max 50%'),
  max_open_positions:   z.number().int().min(1).max(50),
  max_order_value:      z.number().min(1000,   'Minimum ₹1,000'),
  daily_loss_limit_pct: z.number().min(0.1).max(20, 'Max 20%'),
  daily_loss_limit:     z.number().min(0),
})
type FormValues = z.infer<typeof schema>

// ── Data ──────────────────────────────────────────────────────────────────────

async function fetchRisk(): Promise<AlgoRisk> {
  const snap = await getDoc(doc(db, 'app_config', 'algo_risk'))
  return (snap.data() ?? {
    algo_enabled: false, paper_trading: false,
    max_open_positions: 5, max_order_value: 50_000,
    daily_loss_limit: 3_000, daily_loss_limit_pct: 3,
    total_capital: 1_00_000, position_size_pct: 5,
  }) as AlgoRisk
}

// ── Field components ──────────────────────────────────────────────────────────

function FieldGroup({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <div className="flex items-center gap-2">
        <label className="block text-[11px] font-semibold uppercase tracking-wider text-gray-400">{label}</label>
        {hint && (
          <span className="group relative">
            <Info className="h-3 w-3 text-gray-600 cursor-help" />
            <span className="absolute bottom-5 left-0 z-10 hidden w-48 rounded-lg border border-gray-700 bg-gray-800 p-2 text-[11px] text-gray-300 shadow-lg group-hover:block">
              {hint}
            </span>
          </span>
        )}
      </div>
      {children}
    </div>
  )
}

function NumberInput({ value, onChange, prefix, suffix, step = 1, min = 0 }: {
  value: number; onChange: (v: number) => void;
  prefix?: string; suffix?: string; step?: number; min?: number;
}) {
  return (
    <div className="flex items-center overflow-hidden rounded-lg border border-gray-700 bg-gray-800 focus-within:ring-2 focus-within:ring-indigo-500">
      {prefix && <span className="border-r border-gray-700 bg-gray-750 px-3 py-2.5 text-sm text-gray-400">{prefix}</span>}
      <input
        type="number" step={step} min={min}
        value={value}
        onChange={e => onChange(parseFloat(e.target.value) || 0)}
        className="flex-1 bg-transparent px-3 py-2.5 text-sm text-white focus:outline-none"
      />
      {suffix && <span className="border-l border-gray-700 px-3 py-2.5 text-sm text-gray-400">{suffix}</span>}
    </div>
  )
}

function Toggle({ checked, onChange, label, sub }: {
  checked: boolean; onChange: (v: boolean) => void; label: string; sub?: string;
}) {
  return (
    <div className="flex items-center justify-between rounded-xl border border-gray-800 bg-gray-800/50 px-4 py-3">
      <div>
        <p className="text-sm font-semibold text-white">{label}</p>
        {sub && <p className="mt-0.5 text-[11px] text-gray-500">{sub}</p>}
      </div>
      <button type="button" onClick={() => onChange(!checked)}
        className={cn('relative inline-flex h-6 w-11 items-center rounded-full transition-colors',
          checked ? 'bg-indigo-600' : 'bg-gray-700')}>
        <span className={cn('inline-block h-4 w-4 rounded-full bg-white shadow transition-transform',
          checked ? 'translate-x-6' : 'translate-x-1')} />
      </button>
    </div>
  )
}

// ── Page ──────────────────────────────────────────────────────────────────────

export default function RiskControlsPage() {
  const qc                   = useQueryClient()
  const [toast, setToast]    = useState<{ ok: boolean; msg: string } | null>(null)

  const { data: risk, isLoading } = useQuery<AlgoRisk>({
    queryKey: ['algo_risk'],
    queryFn:  fetchRisk,
  })

  const {
    handleSubmit, watch, setValue,
    formState: { errors, isDirty },
    reset,
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    values: risk ? {
      algo_enabled:         risk.algo_enabled         ?? false,
      paper_trading:        risk.paper_trading        ?? false,
      total_capital:        risk.total_capital        ?? 1_00_000,
      position_size_pct:    risk.position_size_pct    ?? 5,
      max_open_positions:   risk.max_open_positions   ?? 5,
      max_order_value:      risk.max_order_value      ?? 50_000,
      daily_loss_limit_pct: risk.daily_loss_limit_pct ?? 3,
      daily_loss_limit:     risk.daily_loss_limit     ?? 3_000,
    } : undefined,
  })

  // Auto-compute daily_loss_limit when capital or pct changes
  const capital = watch('total_capital') || 0
  const lossPct = watch('daily_loss_limit_pct') || 0

  const save = useMutation({
    mutationFn: async (values: FormValues) => {
      // Recompute daily_loss_limit from capital × pct before saving
      const computedLimit = Math.round(values.total_capital * values.daily_loss_limit_pct / 100)
      await setDoc(doc(db, 'app_config', 'algo_risk'), {
        ...values,
        daily_loss_limit: computedLimit,
        updated_at:       serverTimestamp(),
      }, { merge: false })
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['algo_risk'] })
      setToast({ ok: true, msg: 'Risk config saved.' })
      reset(watch())   // mark form as clean
    },
    onError: (e: Error) => setToast({ ok: false, msg: e.message }),
  })

  if (isLoading) {
    return (
      <div className="space-y-4">
        {Array.from({ length: 4 }).map((_, i) => (
          <div key={i} className="h-20 animate-pulse rounded-xl bg-gray-800" />
        ))}
      </div>
    )
  }

  return (
    <form onSubmit={handleSubmit(v => save.mutate(v))} className="space-y-6">

      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-bold text-white">Risk Controls</h1>
          <p className="mt-0.5 text-xs text-gray-500">
            app_config/algo_risk · Last saved: {fmtDate(risk?.updated_at as Parameters<typeof fmtDate>[0])}
          </p>
        </div>
        <Button type="submit" icon={Save} loading={save.isPending} disabled={!isDirty}>
          Save Changes
        </Button>
      </div>

      {/* Toast */}
      {toast && (
        <div className={cn('flex items-center gap-2 rounded-lg px-4 py-3 text-sm',
          toast.ok ? 'border border-emerald-800 bg-emerald-950 text-emerald-300'
                   : 'border border-red-800 bg-red-950 text-red-300')}>
          {toast.ok ? <CheckCircle2 className="h-4 w-4 shrink-0" /> : <AlertTriangle className="h-4 w-4 shrink-0" />}
          {toast.msg}
        </div>
      )}

      {/* ── Engine toggles ─────────────────────────────────────────────────── */}
      <section className="rounded-xl border border-gray-800 bg-gray-900 p-5 space-y-3">
        <p className="text-xs font-bold uppercase tracking-wider text-gray-500 mb-1">Engine State</p>
        <Toggle
          checked={watch('algo_enabled')}
          onChange={v => setValue('algo_enabled', v, { shouldDirty: true })}
          label="Algo Engine"
          sub="Master switch — when OFF, onStrategyEntryCheck and onPositionMonitor do nothing"
        />
        <Toggle
          checked={watch('paper_trading')}
          onChange={v => setValue('paper_trading', v, { shouldDirty: true })}
          label={<span className="flex items-center gap-1.5"><FlaskConical className="h-4 w-4 text-amber-400" />Paper Trading Mode</span> as any}
          sub="Orders are simulated — no real trades sent to Angel One"
        />
        {watch('paper_trading') && (
          <div className="flex items-start gap-2 rounded-lg border border-amber-800 bg-amber-950/30 px-4 py-3 text-sm text-amber-300">
            <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0" />
            Paper trading is ON. All orders will be simulated — no real money will move.
          </div>
        )}
      </section>

      {/* ── Capital ───────────────────────────────────────────────────────── */}
      <section className="rounded-xl border border-gray-800 bg-gray-900 p-5 space-y-4">
        <p className="text-xs font-bold uppercase tracking-wider text-gray-500">Capital & Position Sizing</p>

        <div className="grid gap-4 sm:grid-cols-2">
          <FieldGroup label="Total Capital"
            hint="The total trading capital. Used to compute position sizes and daily loss limits.">
            <NumberInput
              prefix="₹" step={1000} min={1000}
              value={watch('total_capital')}
              onChange={v => setValue('total_capital', v, { shouldDirty: true })}
            />
            {errors.total_capital && <p className="text-xs text-red-400">{errors.total_capital.message}</p>}
          </FieldGroup>

          <FieldGroup label="Position Size per Trade"
            hint="% of total capital allocated per strategy entry.">
            <NumberInput
              suffix="%" step={0.5} min={0.5}
              value={watch('position_size_pct')}
              onChange={v => setValue('position_size_pct', v, { shouldDirty: true })}
            />
            {errors.position_size_pct && <p className="text-xs text-red-400">{errors.position_size_pct.message}</p>}
            <p className="text-[11px] text-gray-600">
              = ₹{Math.round(capital * watch('position_size_pct') / 100).toLocaleString('en-IN')} per trade
            </p>
          </FieldGroup>
        </div>
      </section>

      {/* ── Order limits ──────────────────────────────────────────────────── */}
      <section className="rounded-xl border border-gray-800 bg-gray-900 p-5 space-y-4">
        <p className="text-xs font-bold uppercase tracking-wider text-gray-500">Order Limits</p>

        <div className="grid gap-4 sm:grid-cols-2">
          <FieldGroup label="Max Open Positions"
            hint="Hard cap on how many strategies can be in_position simultaneously per user.">
            <NumberInput
              step={1} min={1}
              value={watch('max_open_positions')}
              onChange={v => setValue('max_open_positions', v, { shouldDirty: true })}
            />
            {errors.max_open_positions && <p className="text-xs text-red-400">{errors.max_open_positions.message}</p>}
          </FieldGroup>

          <FieldGroup label="Max Order Value"
            hint="Single order value cap. Orders exceeding this are blocked by the risk manager.">
            <NumberInput
              prefix="₹" step={1000} min={1000}
              value={watch('max_order_value')}
              onChange={v => setValue('max_order_value', v, { shouldDirty: true })}
            />
            {errors.max_order_value && <p className="text-xs text-red-400">{errors.max_order_value.message}</p>}
          </FieldGroup>
        </div>
      </section>

      {/* ── Daily loss limit ───────────────────────────────────────────────── */}
      <section className="rounded-xl border border-gray-800 bg-gray-900 p-5 space-y-4">
        <p className="text-xs font-bold uppercase tracking-wider text-gray-500">Daily Loss Limit</p>

        <div className="grid gap-4 sm:grid-cols-2">
          <FieldGroup label="Daily Loss Limit %"
            hint="When a user's total SL hits today exceed this % of capital, no new entries are placed.">
            <NumberInput
              suffix="%" step={0.5} min={0.1}
              value={watch('daily_loss_limit_pct')}
              onChange={v => setValue('daily_loss_limit_pct', v, { shouldDirty: true })}
            />
          </FieldGroup>

          <FieldGroup label="Computed ₹ Limit (auto)" hint="Derived from capital × pct. Saved automatically.">
            <div className="flex items-center rounded-lg border border-gray-700 bg-gray-800/50 px-3 py-2.5">
              <span className="text-sm font-bold text-indigo-400">
                ₹{Math.round(capital * lossPct / 100).toLocaleString('en-IN')}
              </span>
              <Badge variant="muted" className="ml-auto">auto</Badge>
            </div>
          </FieldGroup>
        </div>

        {/* Risk summary */}
        <div className="rounded-lg bg-gray-800/40 border border-gray-800 p-4">
          <div className="flex items-center gap-2 mb-2">
            <ShieldCheck className="h-4 w-4 text-indigo-400" />
            <span className="text-xs font-semibold text-gray-300">Risk Summary</span>
          </div>
          <div className="grid grid-cols-2 gap-2 text-xs">
            {[
              ['Capital', `₹${(watch('total_capital') || 0).toLocaleString('en-IN')}`],
              ['Per trade', `₹${Math.round((watch('total_capital') || 0) * (watch('position_size_pct') || 0) / 100).toLocaleString('en-IN')}`],
              ['Max positions', `${watch('max_open_positions') || 0} × lots`],
              ['Max exposure', `₹${Math.round((watch('max_order_value') || 0) * (watch('max_open_positions') || 0)).toLocaleString('en-IN')}`],
              ['Daily loss cap', `₹${Math.round((watch('total_capital') || 0) * (watch('daily_loss_limit_pct') || 0) / 100).toLocaleString('en-IN')}`],
              ['Max order', `₹${(watch('max_order_value') || 0).toLocaleString('en-IN')}`],
            ].map(([l, v]) => (
              <div key={l} className="flex justify-between">
                <span className="text-gray-500">{l}</span>
                <span className="font-semibold text-white">{v}</span>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Unsaved changes banner */}
      {isDirty && (
        <div className="sticky bottom-4 flex items-center justify-between rounded-xl border border-amber-800 bg-amber-950/80 px-5 py-3 shadow-xl backdrop-blur">
          <div className="flex items-center gap-2 text-sm text-amber-300">
            <AlertTriangle className="h-4 w-4 shrink-0" />
            You have unsaved changes
          </div>
          <div className="flex gap-2">
            <Button type="button" variant="ghost" size="sm" onClick={() => reset()}>Discard</Button>
            <Button type="submit" size="sm" loading={save.isPending}>Save Changes</Button>
          </div>
        </div>
      )}
    </form>
  )
}
