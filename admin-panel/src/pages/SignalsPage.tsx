import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import {
  Plus, Pencil, Trash2, Radio,
  Eye, EyeOff, AlertTriangle, CheckCircle2, X,
  ChevronDown, ChevronUp, Search,
} from 'lucide-react'
import {
  useSignalsLive, useCreateSignal, useUpdateSignal,
  usePublishSignal, useDeleteSignal,
  type AlgoSignal, type SignalFormValues,
} from '@/hooks/useSignals'
import { fmtDate, cn } from '@/lib/utils'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'

// ── Form schema ───────────────────────────────────────────────────────────────

const schema = z.object({
  title:        z.string().min(3, 'Title is required'),
  category:     z.enum(['stocks', 'options', 'futures', 'commodity']),
  type:         z.enum(['intraday', 'short_term', 'medium_term']),
  source:       z.literal('admin'),
  status:       z.literal('live'),
  is_published: z.boolean(),
  auto_execute: z.boolean(),
  plan_ids:     z.array(z.string()).min(1, 'Select at least one plan'),
  confidence:   z.enum(['low', 'medium', 'high']),
  body:         z.string().optional(),
  tags:         z.array(z.string()).optional(),
  stock: z.object({
    name:     z.string().min(1, 'Stock name required'),
    symbol:   z.string().min(1, 'Symbol required').toUpperCase(),
    exchange: z.enum(['NSE', 'BSE', 'NFO', 'MCX', 'BFO']),
  }),
  trade: z.object({
    action:       z.enum(['BUY', 'SELL']),
    entry_price:  z.number({ invalid_type_error: 'Enter a valid price' }).positive(),
    order_type:   z.enum(['LIMIT', 'MARKET', 'SL', 'SL-M']),
    product_type: z.enum(['CNC', 'MIS', 'NRML']),
    validity:     z.enum(['DAY', 'IOC']),
    lot_size:     z.number().nullable().optional(),
    option_type:  z.string().nullable().optional(),
    strike_price: z.number().nullable().optional(),
    expiry_date:  z.string().nullable().optional(),
  }),
  analysis: z.object({
    target:   z.number({ invalid_type_error: 'Enter target' }).positive(),
    target2:  z.number().nullable().optional(),
    stoploss: z.number({ invalid_type_error: 'Enter stop-loss' }).positive(),
    duration: z.string().optional(),
  }),
})

type FormValues = z.infer<typeof schema>

const DEFAULT_VALUES: FormValues = {
  title: '', category: 'stocks', type: 'short_term',
  source: 'admin', status: 'live',
  is_published: false, auto_execute: false,
  plan_ids: ['silver_algo'],
  confidence: 'medium', body: '',  tags: [],
  stock:    { name: '', symbol: '', exchange: 'NSE' },
  trade:    { action: 'BUY', entry_price: 0, order_type: 'LIMIT', product_type: 'CNC', validity: 'DAY', lot_size: null },
  analysis: { target: 0, stoploss: 0, target2: null, duration: '2-4 weeks' },
}

// ── Status badge ──────────────────────────────────────────────────────────────

function signalBadge(sig: AlgoSignal) {
  if (sig.is_published) return <Badge variant="success">LIVE</Badge>
  return <Badge variant="muted">DRAFT</Badge>
}

function categoryBadge(cat: string) {
  const map: Record<string, string> = {
    stocks: 'bg-indigo-600/15 text-indigo-400', options: 'bg-purple-600/15 text-purple-400',
    futures: 'bg-sky-600/15 text-sky-400', commodity: 'bg-amber-600/15 text-amber-400',
  }
  return (
    <span className={cn('rounded-full px-2 py-0.5 text-[10px] font-bold uppercase', map[cat] ?? 'bg-gray-700 text-gray-400')}>
      {cat}
    </span>
  )
}

// ── Field helpers ─────────────────────────────────────────────────────────────

function Field({ label, error, children }: { label: string; error?: string; children: React.ReactNode }) {
  return (
    <div className="space-y-1.5">
      <label className="block text-[11px] font-semibold uppercase tracking-wider text-gray-500">{label}</label>
      {children}
      {error && <p className="text-xs text-red-400">{error}</p>}
    </div>
  )
}

const inputCls = (err?: string) => cn(
  'w-full rounded-lg border bg-gray-800 px-3 py-2 text-sm text-white placeholder-gray-600',
  'focus:outline-none focus:ring-2 focus:ring-indigo-500',
  err ? 'border-red-600' : 'border-gray-700',
)

const selectCls = inputCls

// ── Signal form modal ─────────────────────────────────────────────────────────

interface FormModalProps {
  editSignal?: AlgoSignal | null
  onClose:     () => void
}

function SignalFormModal({ editSignal, onClose }: FormModalProps) {
  const isEdit   = !!editSignal
  const create   = useCreateSignal()
  const update   = useUpdateSignal()
  const isPending = create.isPending || update.isPending

  const [toast, setToast] = useState<{ ok: boolean; msg: string } | null>(null)
  const [tagsInput, setTagsInput] = useState(editSignal?.tags?.join(', ') ?? '')
  const [showAdvanced, setShowAdvanced] = useState(false)

  const {
    register, handleSubmit, watch, setValue,
    formState: { errors },
  } = useForm<FormValues>({
    resolver: zodResolver(schema),
    defaultValues: editSignal
      ? {
          ...DEFAULT_VALUES,
          title:        editSignal.title        ?? '',
          category:     (editSignal.category    as FormValues['category'])    ?? 'stocks',
          type:         (editSignal.type        as FormValues['type'])        ?? 'short_term',
          is_published: editSignal.is_published ?? false,
          auto_execute: editSignal.auto_execute ?? false,
          plan_ids:     editSignal.plan_ids     ?? ['silver_algo'],
          confidence:   (editSignal.confidence  as FormValues['confidence'])  ?? 'medium',
          body:         editSignal.body         ?? '',
          tags:         editSignal.tags         ?? [],
          stock:        { name: editSignal.stock?.name ?? '', symbol: editSignal.stock?.symbol ?? '', exchange: (editSignal.stock?.exchange as FormValues['stock']['exchange']) ?? 'NSE' },
          trade:        {
            action:       (editSignal.trade?.action as FormValues['trade']['action']) ?? 'BUY',
            entry_price:  editSignal.trade?.entry_price  ?? 0,
            order_type:   (editSignal.trade?.order_type  as FormValues['trade']['order_type'])  ?? 'LIMIT',
            product_type: (editSignal.trade?.product_type as FormValues['trade']['product_type']) ?? 'CNC',
            validity:     (editSignal.trade?.validity    as FormValues['trade']['validity'])    ?? 'DAY',
            lot_size:     editSignal.trade?.lot_size     ?? null,
          },
          analysis: {
            target:   editSignal.analysis?.target   ?? 0,
            target2:  editSignal.analysis?.target2  ?? null,
            stoploss: editSignal.analysis?.stoploss ?? 0,
            duration: editSignal.analysis?.duration ?? '',
          },
        }
      : DEFAULT_VALUES,
  })

  const entryPrice = watch('trade.entry_price') || 0
  const target     = watch('analysis.target')    || 0
  const stoploss   = watch('analysis.stoploss')  || 0
  void watch('trade.action') // watch triggers re-render when action changes

  // R:R ratio
  const rr = (entryPrice > 0 && stoploss > 0 && target > 0)
    ? (Math.abs(target - entryPrice) / Math.abs(entryPrice - stoploss)).toFixed(2)
    : null

  const onSubmit = async (values: FormValues) => {
    // Parse comma-separated tags
    const parsedTags = tagsInput
      .split(',')
      .map(t => t.trim().toLowerCase())
      .filter(Boolean)
    const payload: SignalFormValues = {
      ...values,
      tags: parsedTags,
      performance: {
        gain_so_far:    0,
        potential_left: entryPrice > 0 && target > 0
          ? +((Math.abs(target - entryPrice) / entryPrice) * 100).toFixed(2)
          : 0,
      },
    }

    try {
      if (isEdit) {
        await update.mutateAsync({ id: editSignal!.id, values: payload })
      } else {
        await create.mutateAsync(payload)
      }
      setToast({ ok: true, msg: isEdit ? 'Signal updated.' : 'Signal created!' })
      setTimeout(onClose, 800)
    } catch (e: unknown) {
      setToast({ ok: false, msg: e instanceof Error ? e.message : 'Write failed' })
    }
  }

  return (
    <div className="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto bg-black/70 p-4 pt-8">
      <div className="w-full max-w-2xl rounded-2xl border border-gray-800 bg-gray-900 shadow-2xl">

        {/* Header */}
        <div className="flex items-center justify-between border-b border-gray-800 px-6 py-4">
          <h2 className="text-base font-bold text-white">
            {isEdit ? 'Edit Signal' : 'Create Signal'}
          </h2>
          <button onClick={onClose} className="rounded-md p-1 text-gray-500 hover:text-white">
            <X className="h-5 w-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-5 px-6 py-5">

          {/* Toast */}
          {toast && (
            <div className={cn(
              'flex items-center gap-2 rounded-lg px-4 py-3 text-sm',
              toast.ok
                ? 'border border-emerald-800 bg-emerald-950 text-emerald-300'
                : 'border border-red-800 bg-red-950 text-red-300',
            )}>
              {toast.ok
                ? <CheckCircle2 className="h-4 w-4 shrink-0" />
                : <AlertTriangle className="h-4 w-4 shrink-0" />}
              {toast.msg}
            </div>
          )}

          {/* Title */}
          <Field label="Signal Title" error={errors.title?.message}>
            <input {...register('title')} placeholder="RELIANCE — Resistance Breakout"
              className={inputCls(errors.title?.message)} />
          </Field>

          {/* Category / Type / Confidence row */}
          <div className="grid grid-cols-3 gap-3">
            <Field label="Category" error={errors.category?.message}>
              <select {...register('category')} className={selectCls()}>
                {['stocks','options','futures','commodity'].map(v => (
                  <option key={v} value={v}>{v}</option>
                ))}
              </select>
            </Field>
            <Field label="Type" error={errors.type?.message}>
              <select {...register('type')} className={selectCls()}>
                {['intraday','short_term','medium_term'].map(v => (
                  <option key={v} value={v}>{v.replace('_', ' ')}</option>
                ))}
              </select>
            </Field>
            <Field label="Confidence" error={errors.confidence?.message}>
              <select {...register('confidence')} className={selectCls()}>
                {['low','medium','high'].map(v => (
                  <option key={v} value={v}>{v}</option>
                ))}
              </select>
            </Field>
          </div>

          {/* Stock details */}
          <div className="rounded-xl border border-gray-800 p-4 space-y-3">
            <p className="text-[11px] font-bold uppercase tracking-wider text-gray-500">Instrument</p>
            <div className="grid grid-cols-3 gap-3">
              <Field label="Stock Name" error={errors.stock?.name?.message}>
                <input {...register('stock.name')} placeholder="Reliance Industries"
                  className={inputCls(errors.stock?.name?.message)} />
              </Field>
              <Field label="Symbol" error={errors.stock?.symbol?.message}>
                <input {...register('stock.symbol')} placeholder="RELIANCE"
                  className={inputCls(errors.stock?.symbol?.message)}
                  style={{ textTransform: 'uppercase' }} />
              </Field>
              <Field label="Exchange" error={errors.stock?.exchange?.message}>
                <select {...register('stock.exchange')} className={selectCls()}>
                  {['NSE','BSE','NFO','MCX','BFO'].map(v => (
                    <option key={v} value={v}>{v}</option>
                  ))}
                </select>
              </Field>
            </div>
          </div>

          {/* Trade details */}
          <div className="rounded-xl border border-gray-800 p-4 space-y-3">
            <p className="text-[11px] font-bold uppercase tracking-wider text-gray-500">Trade Setup</p>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
              <Field label="Action" error={errors.trade?.action?.message}>
                <select {...register('trade.action')} className={selectCls()}>
                  <option value="BUY">BUY</option>
                  <option value="SELL">SELL</option>
                </select>
              </Field>
              <Field label="Order Type" error={errors.trade?.order_type?.message}>
                <select {...register('trade.order_type')} className={selectCls()}>
                  {['LIMIT','MARKET','SL','SL-M'].map(v => (
                    <option key={v} value={v}>{v}</option>
                  ))}
                </select>
              </Field>
              <Field label="Product" error={errors.trade?.product_type?.message}>
                <select {...register('trade.product_type')} className={selectCls()}>
                  {['CNC','MIS','NRML'].map(v => (
                    <option key={v} value={v}>{v}</option>
                  ))}
                </select>
              </Field>
              <Field label="Validity" error={errors.trade?.validity?.message}>
                <select {...register('trade.validity')} className={selectCls()}>
                  <option value="DAY">DAY</option>
                  <option value="IOC">IOC</option>
                </select>
              </Field>
            </div>
            <div className="grid grid-cols-3 gap-3">
              <Field label="Entry Price ₹" error={errors.trade?.entry_price?.message}>
                <input type="number" step="0.01"
                  {...register('trade.entry_price', { valueAsNumber: true })}
                  placeholder="2940" className={inputCls(errors.trade?.entry_price?.message)} />
              </Field>
              <Field label="Target ₹" error={errors.analysis?.target?.message}>
                <input type="number" step="0.01"
                  {...register('analysis.target', { valueAsNumber: true })}
                  placeholder="3120" className={inputCls(errors.analysis?.target?.message)} />
              </Field>
              <Field label="Stop Loss ₹" error={errors.analysis?.stoploss?.message}>
                <input type="number" step="0.01"
                  {...register('analysis.stoploss', { valueAsNumber: true })}
                  placeholder="2860" className={inputCls(errors.analysis?.stoploss?.message)} />
              </Field>
            </div>
            {/* R:R preview */}
            {rr && (
              <div className="flex items-center gap-4 rounded-lg bg-gray-800 px-3 py-2 text-xs">
                <span className="text-gray-400">R:R ratio</span>
                <span className={cn('font-bold', parseFloat(rr) >= 1.5 ? 'text-emerald-400' : 'text-amber-400')}>
                  1 : {rr}
                </span>
                <span className="text-gray-400">Potential</span>
                <span className="font-bold text-emerald-400">
                  {entryPrice > 0 ? `+${((target - entryPrice) / entryPrice * 100).toFixed(1)}%` : '—'}
                </span>
                <span className="text-gray-400">Risk</span>
                <span className="font-bold text-red-400">
                  {entryPrice > 0 ? `-${(Math.abs(entryPrice - stoploss) / entryPrice * 100).toFixed(1)}%` : '—'}
                </span>
              </div>
            )}
          </div>

          {/* Plan IDs */}
          <Field label="Plans (which subscribers see this)" error={errors.plan_ids?.message?.toString()}>
            <div className="flex flex-wrap gap-2">
              {['silver_algo', 'gold_algo', 'platinum_algo'].map(planId => {
                const checked = watch('plan_ids')?.includes(planId)
                return (
                  <button key={planId} type="button"
                    onClick={() => {
                      const curr = watch('plan_ids') ?? []
                      setValue('plan_ids', checked
                        ? curr.filter(p => p !== planId)
                        : [...curr, planId])
                    }}
                    className={cn(
                      'rounded-full border px-3 py-1.5 text-xs font-semibold transition-colors',
                      checked
                        ? 'border-indigo-500 bg-indigo-600/20 text-indigo-300'
                        : 'border-gray-700 bg-gray-800 text-gray-400 hover:border-gray-600',
                    )}
                  >
                    {planId}
                  </button>
                )
              })}
            </div>
          </Field>

          {/* Auto-execute + Publish toggles */}
          <div className="grid grid-cols-2 gap-3">
            {[
              { field: 'auto_execute' as const, label: 'Auto Execute', sub: 'Place orders automatically for all subscribers' },
              { field: 'is_published' as const, label: 'Publish Now',  sub: 'Trigger push notification & make visible in app' },
            ].map(({ field, label, sub }) => (
              <div key={field}
                className="flex items-center justify-between rounded-xl border border-gray-800 bg-gray-800/50 px-4 py-3">
                <div>
                  <p className="text-xs font-semibold text-white">{label}</p>
                  <p className="mt-0.5 text-[11px] text-gray-500">{sub}</p>
                </div>
                <button type="button"
                  onClick={() => setValue(field, !watch(field))}
                  className={cn(
                    'relative inline-flex h-6 w-11 items-center rounded-full transition-colors',
                    watch(field) ? 'bg-indigo-600' : 'bg-gray-700',
                  )}>
                  <span className={cn(
                    'inline-block h-4 w-4 rounded-full bg-white shadow transition-transform',
                    watch(field) ? 'translate-x-6' : 'translate-x-1',
                  )} />
                </button>
              </div>
            ))}
          </div>

          {/* Advanced (description, tags, target2, duration) */}
          <button type="button"
            onClick={() => setShowAdvanced(!showAdvanced)}
            className="flex w-full items-center justify-between rounded-lg border border-gray-800 px-4 py-2.5 text-xs font-semibold text-gray-400 hover:bg-gray-800">
            <span>Advanced fields (description, tags, T2, duration)</span>
            {showAdvanced ? <ChevronUp className="h-4 w-4" /> : <ChevronDown className="h-4 w-4" />}
          </button>

          {showAdvanced && (
            <div className="space-y-3">
              <Field label="Description / Notes">
                <textarea rows={3} {...register('body')}
                  placeholder="Entry rationale, technicals, risk notes…"
                  className={cn(inputCls(), 'resize-none')} />
              </Field>
              <div className="grid grid-cols-2 gap-3">
                <Field label="Target 2 ₹ (optional)">
                  <input type="number" step="0.01"
                    {...register('analysis.target2', { valueAsNumber: true, setValueAs: v => v === '' ? null : Number(v) })}
                    placeholder="3280" className={inputCls()} />
                </Field>
                <Field label="Duration">
                  <input {...register('analysis.duration')} placeholder="2-3 weeks" className={inputCls()} />
                </Field>
              </div>
              <Field label="Tags (comma separated)">
                <input
                  value={tagsInput}
                  onChange={e => setTagsInput(e.target.value)}
                  placeholder="breakout, momentum, technical"
                  className={inputCls()}
                />
              </Field>
            </div>
          )}

          {/* Footer buttons */}
          <div className="flex justify-end gap-3 border-t border-gray-800 pt-4">
            <Button type="button" variant="ghost" onClick={onClose}>Cancel</Button>
            <Button type="submit" variant="primary" loading={isPending}>
              {isEdit ? 'Save Changes' : 'Create Signal'}
            </Button>
          </div>
        </form>
      </div>
    </div>
  )
}

// ── Delete confirm ────────────────────────────────────────────────────────────

function DeleteConfirm({ signal, onClose }: { signal: AlgoSignal; onClose: () => void }) {
  const del = useDeleteSignal()

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4">
      <div className="w-full max-w-sm rounded-2xl border border-gray-800 bg-gray-900 p-6 shadow-2xl">
        <div className="mb-4 flex h-11 w-11 items-center justify-center rounded-xl bg-red-600/15">
          <Trash2 className="h-5 w-5 text-red-400" />
        </div>
        <h3 className="text-base font-bold text-white">Delete signal?</h3>
        <p className="mt-1 text-sm text-gray-400">
          <strong className="text-white">{signal.stock?.symbol ?? signal.title}</strong> will be permanently deleted.
          This cannot be undone.
        </p>
        <div className="mt-5 flex gap-3">
          <Button variant="ghost" className="flex-1" onClick={onClose}>Cancel</Button>
          <Button variant="danger" className="flex-1"
            loading={del.isPending}
            onClick={async () => { await del.mutateAsync(signal.id); onClose() }}>
            Delete
          </Button>
        </div>
      </div>
    </div>
  )
}

// ── Main page ─────────────────────────────────────────────────────────────────

export default function SignalsPage() {
  const { signals, loading, error } = useSignalsLive()
  const publishMut = usePublishSignal()

  const [search,     setSearch]     = useState('')
  const [filterCat,  setFilterCat]  = useState<string>('all')
  const [filterPub,  setFilterPub]  = useState<string>('all')
  const [showForm,   setShowForm]   = useState(false)
  const [editTarget, setEditTarget] = useState<AlgoSignal | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<AlgoSignal | null>(null)

  const filtered = signals.filter(s => {
    const q = search.toLowerCase()
    const matchSearch = !q ||
      s.stock?.symbol?.toLowerCase().includes(q) ||
      s.stock?.name?.toLowerCase().includes(q) ||
      s.title?.toLowerCase().includes(q)
    const matchCat = filterCat === 'all' || s.category === filterCat
    const matchPub = filterPub === 'all' ||
      (filterPub === 'live'  && s.is_published) ||
      (filterPub === 'draft' && !s.is_published)
    return matchSearch && matchCat && matchPub
  })

  const liveCount  = signals.filter(s => s.is_published).length
  const draftCount = signals.filter(s => !s.is_published).length

  return (
    <div className="space-y-5">

      {/* Header */}
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-xl font-bold text-white">Signals</h1>
          <p className="mt-0.5 text-xs text-gray-500">
            {signals.length} total · {liveCount} live · {draftCount} draft
          </p>
        </div>
        <Button icon={Plus} onClick={() => { setEditTarget(null); setShowForm(true) }}>
          New Signal
        </Button>
      </div>

      {/* Filters */}
      <div className="flex flex-wrap gap-2">
        {/* Search */}
        <div className="relative min-w-[200px]">
          <Search className="absolute left-3 top-1/2 h-3.5 w-3.5 -translate-y-1/2 text-gray-500" />
          <input
            value={search}
            onChange={e => setSearch(e.target.value)}
            placeholder="Search symbol or name…"
            className="w-full rounded-lg border border-gray-700 bg-gray-800 py-2 pl-9 pr-3 text-sm text-white placeholder-gray-600 focus:outline-none focus:ring-2 focus:ring-indigo-500"
          />
        </div>
        {/* Category filter */}
        <select value={filterCat} onChange={e => setFilterCat(e.target.value)}
          className="rounded-lg border border-gray-700 bg-gray-800 px-3 py-2 text-sm text-white focus:outline-none focus:ring-2 focus:ring-indigo-500">
          <option value="all">All Categories</option>
          {['stocks','options','futures','commodity'].map(v => (
            <option key={v} value={v}>{v}</option>
          ))}
        </select>
        {/* Status filter */}
        <select value={filterPub} onChange={e => setFilterPub(e.target.value)}
          className="rounded-lg border border-gray-700 bg-gray-800 px-3 py-2 text-sm text-white focus:outline-none focus:ring-2 focus:ring-indigo-500">
          <option value="all">All Status</option>
          <option value="live">Live</option>
          <option value="draft">Draft</option>
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
            {Array.from({ length: 5 }).map((_, i) => (
              <div key={i} className="h-16 animate-pulse bg-gray-800/60" style={{ opacity: 1 - i * 0.15 }} />
            ))}
          </div>
        ) : filtered.length === 0 ? (
          <div className="flex flex-col items-center gap-2 py-16 text-gray-600">
            <Radio className="h-8 w-8" />
            <p className="text-sm">No signals found</p>
            <button onClick={() => { setSearch(''); setFilterCat('all'); setFilterPub('all') }}
              className="text-xs text-indigo-400 hover:underline">Clear filters</button>
          </div>
        ) : (
          <div className="overflow-x-auto">
            <table className="w-full text-sm">
              <thead>
                <tr className="border-b border-gray-800 text-left text-[11px] font-semibold uppercase tracking-wider text-gray-500">
                  <th className="px-4 py-3">Signal</th>
                  <th className="px-4 py-3">Category</th>
                  <th className="px-4 py-3">Entry</th>
                  <th className="px-4 py-3">Target / SL</th>
                  <th className="px-4 py-3">Plans</th>
                  <th className="px-4 py-3">Status</th>
                  <th className="px-4 py-3">Posted</th>
                  <th className="px-4 py-3 text-right">Actions</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-gray-800">
                {filtered.map(sig => {
                  const isBuy = (sig.trade?.action ?? 'BUY') === 'BUY'
                  return (
                    <tr key={sig.id} className="hover:bg-gray-800/40 transition-colors">
                      {/* Signal */}
                      <td className="px-4 py-3">
                        <div className="flex flex-col">
                          <span className="font-semibold text-white">
                            {sig.stock?.symbol ?? '—'}
                          </span>
                          <span className="text-[11px] text-gray-500 truncate max-w-[160px]">
                            {sig.stock?.name ?? sig.title ?? '—'}
                          </span>
                        </div>
                      </td>
                      {/* Category */}
                      <td className="px-4 py-3">{categoryBadge(sig.category)}</td>
                      {/* Entry */}
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-1.5">
                          <span className={cn(
                            'rounded px-1.5 py-0.5 text-[10px] font-bold',
                            isBuy ? 'bg-emerald-600/15 text-emerald-400' : 'bg-red-600/15 text-red-400',
                          )}>
                            {sig.trade?.action ?? 'BUY'}
                          </span>
                          <span className="text-gray-200">
                            {sig.trade?.entry_price ? `₹${sig.trade.entry_price}` : '—'}
                          </span>
                        </div>
                        <p className="mt-0.5 text-[11px] text-gray-600">{sig.trade?.order_type}</p>
                      </td>
                      {/* Target / SL */}
                      <td className="px-4 py-3">
                        <div className="text-xs space-y-0.5">
                          <p className="text-emerald-400">
                            T1: {sig.analysis?.target ? `₹${sig.analysis.target}` : '—'}
                          </p>
                          <p className="text-red-400">
                            SL: {sig.analysis?.stoploss ? `₹${sig.analysis.stoploss}` : '—'}
                          </p>
                        </div>
                      </td>
                      {/* Plans */}
                      <td className="px-4 py-3">
                        <div className="flex flex-wrap gap-1">
                          {(sig.plan_ids ?? []).map(p => (
                            <span key={p} className="rounded bg-gray-800 px-1.5 py-0.5 text-[10px] text-gray-400">
                              {p}
                            </span>
                          ))}
                        </div>
                      </td>
                      {/* Status */}
                      <td className="px-4 py-3">
                        <div className="flex items-center gap-1.5">
                          {signalBadge(sig)}
                          {sig.auto_execute && (
                            <Badge variant="info">AUTO</Badge>
                          )}
                        </div>
                      </td>
                      {/* Posted at */}
                      <td className="px-4 py-3 text-xs text-gray-500">
                        {fmtDate(sig.posted_at as Parameters<typeof fmtDate>[0])}
                      </td>
                      {/* Actions */}
                      <td className="px-4 py-3">
                        <div className="flex items-center justify-end gap-2">
                          {/* Publish / Unpublish */}
                          <button
                            onClick={() => publishMut.mutate({ id: sig.id, publish: !sig.is_published })}
                            disabled={publishMut.isPending}
                            title={sig.is_published ? 'Unpublish' : 'Publish'}
                            className={cn(
                              'rounded-lg border p-1.5 transition-colors',
                              sig.is_published
                                ? 'border-amber-700 text-amber-400 hover:bg-amber-900/20'
                                : 'border-emerald-700 text-emerald-400 hover:bg-emerald-900/20',
                            )}
                          >
                            {sig.is_published ? <EyeOff className="h-3.5 w-3.5" /> : <Eye className="h-3.5 w-3.5" />}
                          </button>
                          {/* Edit */}
                          <button
                            onClick={() => { setEditTarget(sig); setShowForm(true) }}
                            title="Edit"
                            className="rounded-lg border border-gray-700 p-1.5 text-gray-400 hover:bg-gray-800 hover:text-white"
                          >
                            <Pencil className="h-3.5 w-3.5" />
                          </button>
                          {/* Delete */}
                          <button
                            onClick={() => setDeleteTarget(sig)}
                            title="Delete"
                            className="rounded-lg border border-gray-700 p-1.5 text-gray-400 hover:border-red-800 hover:bg-red-950 hover:text-red-400"
                          >
                            <Trash2 className="h-3.5 w-3.5" />
                          </button>
                        </div>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </div>

      {/* Modals */}
      {showForm && (
        <SignalFormModal
          editSignal={editTarget}
          onClose={() => { setShowForm(false); setEditTarget(null) }}
        />
      )}
      {deleteTarget && (
        <DeleteConfirm
          signal={deleteTarget}
          onClose={() => setDeleteTarget(null)}
        />
      )}
    </div>
  )
}
