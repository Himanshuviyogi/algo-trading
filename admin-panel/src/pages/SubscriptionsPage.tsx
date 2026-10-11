import { useState } from 'react'
import {
  collection, query, getDocs, doc, updateDoc, addDoc,
  serverTimestamp, orderBy, where, limit,
} from 'firebase/firestore'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import {
  Crown, Users, Plus, Pencil, X,
  CheckCircle2, AlertTriangle, ToggleLeft, ToggleRight,
} from 'lucide-react'
import { db } from '@/lib/firebase'
import { cn } from '@/lib/utils'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'

// ── Types ─────────────────────────────────────────────────────────────────────

interface Plan {
  id:         string
  name:       string
  category:   string
  fcm_topic:  string
  is_active:  boolean
  pricing:    Record<string, number>   // { '1_month': 19900, ... }
  features:   string[]
  created_at: unknown
  // computed
  activeSubCount?: number
}

interface Subscription {
  id:          string
  user_id:     string
  plan_id:     string
  is_active:   boolean
  start_date:  unknown
  expiry_date: unknown
}

// ── Data ──────────────────────────────────────────────────────────────────────

async function fetchPlansWithCounts(): Promise<Plan[]> {
  const [planSnap, subSnap] = await Promise.all([
    getDocs(query(collection(db, 'subscription_plans'), orderBy('created_at', 'desc'))),
    getDocs(query(collection(db, 'subscriptions'), where('is_active', '==', true))),
  ])

  const now = new Date()
  const countByPlan: Record<string, number> = {}
  subSnap.docs.forEach(d => {
    const data  = d.data()
    const exp   = (data.expiry_date as any)?.toDate?.()
    if (exp && exp < now) return
    const pid = data.plan_id as string
    countByPlan[pid] = (countByPlan[pid] ?? 0) + 1
  })

  return planSnap.docs.map(d => ({
    id:             d.id,
    name:           d.data().name          ?? '',
    category:       d.data().category      ?? '',
    fcm_topic:      d.data().fcm_topic     ?? '',
    is_active:      d.data().is_active     ?? false,
    pricing:        (d.data().pricing      ?? {}) as Record<string, number>,
    features:       (d.data().features     ?? []) as string[],
    created_at:     d.data().created_at,
    activeSubCount: countByPlan[d.id] ?? 0,
  }))
}

async function fetchSubscribersForPlan(planId: string): Promise<Subscription[]> {
  const snap = await getDocs(
    query(
      collection(db, 'subscriptions'),
      where('plan_id', '==', planId),
      orderBy('start_date', 'desc'),
      limit(100),
    )
  )
  return snap.docs.map(d => ({
    id:          d.id,
    user_id:     d.data().user_id    as string,
    plan_id:     d.data().plan_id    as string,
    is_active:   d.data().is_active  as boolean,
    start_date:  d.data().start_date,
    expiry_date: d.data().expiry_date,
  }))
}

// ── Plan form schema ──────────────────────────────────────────────────────────

const planSchema = z.object({
  name:       z.string().min(2, 'Name required'),
  category:   z.string().min(1),
  fcm_topic:  z.string().min(1, 'FCM topic required'),
  is_active:  z.boolean(),
  price_1m:   z.number().min(0),
  price_6m:   z.number().min(0),
  price_1y:   z.number().min(0),
  features:   z.string(),   // comma-separated
})
type PlanForm = z.infer<typeof planSchema>

// ── Plan Form Modal ───────────────────────────────────────────────────────────

function PlanModal({ plan, onClose }: { plan?: Plan; onClose: () => void }) {
  const qc      = useQueryClient()
  const isEdit  = !!plan
  const [toast, setToast] = useState<{ ok: boolean; msg: string } | null>(null)

  const { register, handleSubmit, watch, setValue, formState: { errors } } = useForm<PlanForm>({
    resolver: zodResolver(planSchema),
    defaultValues: plan ? {
      name:      plan.name,
      category:  plan.category,
      fcm_topic: plan.fcm_topic,
      is_active: plan.is_active,
      price_1m:  (plan.pricing['1_month']  ?? 0) / 100,
      price_6m:  (plan.pricing['6_month']  ?? 0) / 100,
      price_1y:  (plan.pricing['1_year']   ?? 0) / 100,
      features:  (plan.features ?? []).join(', '),
    } : {
      name: '', category: 'algo', fcm_topic: '',
      is_active: true, price_1m: 0, price_6m: 0, price_1y: 0, features: '',
    },
  })

  const save = useMutation({
    mutationFn: async (values: PlanForm) => {
      const payload = {
        name:      values.name,
        category:  values.category,
        fcm_topic: values.fcm_topic,
        is_active: values.is_active,
        pricing: {
          '1_month': Math.round(values.price_1m * 100),
          '6_month': Math.round(values.price_6m * 100),
          '1_year':  Math.round(values.price_1y * 100),
        },
        features: values.features.split(',').map(s => s.trim()).filter(Boolean),
      }
      if (isEdit) {
        await updateDoc(doc(db, 'subscription_plans', plan!.id), payload)
      } else {
        await addDoc(collection(db, 'subscription_plans'), {
          ...payload, created_at: serverTimestamp(),
        })
      }
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['plans'] })
      setToast({ ok: true, msg: isEdit ? 'Plan updated.' : 'Plan created!' })
      setTimeout(onClose, 700)
    },
    onError: (e: Error) => setToast({ ok: false, msg: e.message }),
  })

  const inputCls = (err?: string) => cn(
    'w-full rounded-lg border bg-gray-800 px-3 py-2 text-sm text-white placeholder-gray-600',
    'focus:outline-none focus:ring-2 focus:ring-indigo-500',
    err ? 'border-red-600' : 'border-gray-700',
  )

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/70 p-4">
      <div className="w-full max-w-lg rounded-2xl border border-gray-800 bg-gray-900 shadow-2xl">
        <div className="flex items-center justify-between border-b border-gray-800 px-6 py-4">
          <h2 className="text-base font-bold text-white">{isEdit ? 'Edit Plan' : 'New Plan'}</h2>
          <button onClick={onClose} className="rounded-md p-1 text-gray-500 hover:text-white">
            <X className="h-5 w-5" />
          </button>
        </div>

        <form onSubmit={handleSubmit(v => save.mutate(v))} className="space-y-4 px-6 py-5">
          {toast && (
            <div className={cn('flex items-center gap-2 rounded-lg px-4 py-3 text-sm',
              toast.ok ? 'border border-emerald-800 bg-emerald-950 text-emerald-300'
                       : 'border border-red-800 bg-red-950 text-red-300')}>
              {toast.ok ? <CheckCircle2 className="h-4 w-4" /> : <AlertTriangle className="h-4 w-4" />}
              {toast.msg}
            </div>
          )}

          <div className="grid grid-cols-2 gap-3">
            <div className="space-y-1.5">
              <label className="block text-[11px] font-semibold uppercase tracking-wider text-gray-500">Plan Name</label>
              <input {...register('name')} placeholder="Gold Algo Plan" className={inputCls(errors.name?.message)} />
              {errors.name && <p className="text-xs text-red-400">{errors.name.message}</p>}
            </div>
            <div className="space-y-1.5">
              <label className="block text-[11px] font-semibold uppercase tracking-wider text-gray-500">FCM Topic</label>
              <input {...register('fcm_topic')} placeholder="algo_gold" className={inputCls(errors.fcm_topic?.message)} />
              {errors.fcm_topic && <p className="text-xs text-red-400">{errors.fcm_topic.message}</p>}
            </div>
          </div>

          <div className="space-y-1.5">
            <label className="block text-[11px] font-semibold uppercase tracking-wider text-gray-500">Category</label>
            <input {...register('category')} placeholder="algo" className={inputCls()} />
          </div>

          <div>
            <label className="mb-2 block text-[11px] font-semibold uppercase tracking-wider text-gray-500">
              Pricing (₹ — enter actual amount, stored as paise)
            </label>
            <div className="grid grid-cols-3 gap-3">
              {([['price_1m','1 Month'], ['price_6m','6 Months'], ['price_1y','1 Year']] as const).map(([field, lbl]) => (
                <div key={field} className="space-y-1">
                  <label className="text-[10px] text-gray-600">{lbl}</label>
                  <input type="number" step="1" {...register(field, { valueAsNumber: true })}
                    placeholder="999" className={inputCls()} />
                </div>
              ))}
            </div>
          </div>

          <div className="space-y-1.5">
            <label className="block text-[11px] font-semibold uppercase tracking-wider text-gray-500">
              Features (comma separated)
            </label>
            <input {...register('features')} placeholder="Auto execution, F&O signals, Risk management"
              className={inputCls()} />
          </div>

          <div className="flex items-center justify-between rounded-xl border border-gray-800 bg-gray-800/50 px-4 py-3">
            <div>
              <p className="text-sm font-semibold text-white">Active</p>
              <p className="text-[11px] text-gray-500">Visible and purchasable in the app</p>
            </div>
            <button type="button" onClick={() => setValue('is_active', !watch('is_active'))}
              className={cn('relative inline-flex h-6 w-11 items-center rounded-full transition-colors',
                watch('is_active') ? 'bg-indigo-600' : 'bg-gray-700')}>
              <span className={cn('inline-block h-4 w-4 rounded-full bg-white shadow transition-transform',
                watch('is_active') ? 'translate-x-6' : 'translate-x-1')} />
            </button>
          </div>

          <div className="flex justify-end gap-3 border-t border-gray-800 pt-4">
            <Button type="button" variant="ghost" onClick={onClose}>Cancel</Button>
            <Button type="submit" variant="primary" loading={save.isPending}>
              {isEdit ? 'Save Changes' : 'Create Plan'}
            </Button>
          </div>
        </form>
      </div>
    </div>
  )
}

// ── Subscribers drawer ────────────────────────────────────────────────────────

function SubscribersDrawer({ plan, onClose }: { plan: Plan; onClose: () => void }) {
  const { data: subs = [], isLoading } = useQuery({
    queryKey: ['subs', plan.id],
    queryFn:  () => fetchSubscribersForPlan(plan.id),
  })

  const now = new Date()

  return (
    <div className="fixed inset-0 z-50 flex justify-end bg-black/60" onClick={onClose}>
      <div className="flex h-full w-full max-w-md flex-col overflow-y-auto border-l border-gray-800 bg-gray-900 shadow-2xl"
        onClick={e => e.stopPropagation()}>
        <div className="flex items-center justify-between border-b border-gray-800 px-6 py-4">
          <div>
            <p className="text-base font-bold text-white">{plan.name}</p>
            <p className="text-xs text-gray-500">{subs.length} subscribers</p>
          </div>
          <button onClick={onClose} className="rounded-md p-1.5 text-gray-400 hover:text-white">
            <X className="h-5 w-5" />
          </button>
        </div>

        <div className="flex-1 p-4 space-y-2">
          {isLoading
            ? Array.from({ length: 5 }).map((_, i) => (
                <div key={i} className="h-12 animate-pulse rounded-lg bg-gray-800" />
              ))
            : subs.length === 0
              ? <p className="py-12 text-center text-sm text-gray-600">No subscribers yet</p>
              : subs.map(s => {
                  const exp    = (s.expiry_date as any)?.toDate?.() as Date | undefined
                  const active = s.is_active && (!exp || exp > now)
                  const daysLeft = exp ? Math.ceil((exp.getTime() - now.getTime()) / 86_400_000) : null
                  return (
                    <div key={s.id} className="flex items-center justify-between rounded-lg border border-gray-800 px-3 py-2.5">
                      <div>
                        <p className="text-sm font-mono text-gray-300">{s.user_id.slice(0, 16)}…</p>
                        <p className="text-[11px] text-gray-600">
                          Expires: {exp ? exp.toLocaleDateString('en-IN') : '—'}
                        </p>
                      </div>
                      <div className="flex items-center gap-2">
                        {daysLeft !== null && daysLeft <= 7 && daysLeft > 0 && (
                          <span className="text-[10px] font-bold text-amber-400">{daysLeft}d left</span>
                        )}
                        <Badge variant={active ? 'success' : 'muted'}>
                          {active ? 'ACTIVE' : 'EXPIRED'}
                        </Badge>
                      </div>
                    </div>
                  )
                })
          }
        </div>
      </div>
    </div>
  )
}

// ── Main page ─────────────────────────────────────────────────────────────────

export default function SubscriptionsPage() {
  const qc   = useQueryClient()
  const [modalPlan, setModalPlan]     = useState<Plan | undefined | null>(null)  // null = hidden, undefined = new
  const [drawerPlan, setDrawerPlan]   = useState<Plan | null>(null)

  const { data: plans = [], isLoading } = useQuery({
    queryKey: ['plans'],
    queryFn:  fetchPlansWithCounts,
    staleTime: 60_000,
  })

  const toggleActive = useMutation({
    mutationFn: ({ id, val }: { id: string; val: boolean }) =>
      updateDoc(doc(db, 'subscription_plans', id), { is_active: val }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['plans'] }),
  })

  const totalSubs = plans.reduce((s, p) => s + (p.activeSubCount ?? 0), 0)

  return (
    <div className="space-y-5">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-xl font-bold text-white">Subscriptions</h1>
          <p className="mt-0.5 text-xs text-gray-500">
            {plans.length} plans · {totalSubs} active subscribers
          </p>
        </div>
        <Button icon={Plus} onClick={() => setModalPlan(undefined)}>New Plan</Button>
      </div>

      {isLoading ? (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {Array.from({ length: 3 }).map((_, i) => (
            <div key={i} className="h-48 animate-pulse rounded-xl bg-gray-800" />
          ))}
        </div>
      ) : (
        <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {plans.map(p => (
            <div key={p.id} className="flex flex-col rounded-xl border border-gray-800 bg-gray-900 p-5">
              {/* Header */}
              <div className="flex items-start justify-between">
                <div className="flex items-center gap-2">
                  <div className="flex h-9 w-9 items-center justify-center rounded-xl bg-indigo-600/15">
                    <Crown className="h-4 w-4 text-indigo-400" />
                  </div>
                  <div>
                    <p className="font-bold text-white">{p.name}</p>
                    <p className="text-[11px] text-gray-500">{p.fcm_topic}</p>
                  </div>
                </div>
                <button onClick={() => toggleActive.mutate({ id: p.id, val: !p.is_active })}>
                  {p.is_active
                    ? <ToggleRight className="h-6 w-6 text-emerald-400" />
                    : <ToggleLeft  className="h-6 w-6 text-gray-600" />}
                </button>
              </div>

              {/* Sub count */}
              <div className="mt-4 flex items-center gap-2">
                <Users className="h-4 w-4 text-gray-500" />
                <span className="text-2xl font-bold text-white">{p.activeSubCount ?? 0}</span>
                <span className="text-xs text-gray-500">active subscribers</span>
              </div>

              {/* Pricing */}
              <div className="mt-3 grid grid-cols-3 gap-1.5">
                {Object.entries(p.pricing).map(([dur, paise]) => (
                  <div key={dur} className="rounded-lg bg-gray-800 px-2 py-1.5 text-center">
                    <p className="text-xs font-bold text-white">₹{paise / 100}</p>
                    <p className="text-[9px] text-gray-600">{dur.replace('_', ' ')}</p>
                  </div>
                ))}
              </div>

              {/* Features */}
              <div className="mt-3 flex flex-wrap gap-1">
                {(p.features ?? []).slice(0, 3).map(f => (
                  <span key={f} className="rounded-full bg-gray-800 px-2 py-0.5 text-[10px] text-gray-400">{f}</span>
                ))}
              </div>

              {/* Actions */}
              <div className="mt-4 flex gap-2 border-t border-gray-800 pt-3">
                <Button size="sm" variant="outline" icon={Users} className="flex-1 justify-center"
                  onClick={() => setDrawerPlan(p)}>
                  Subscribers
                </Button>
                <Button size="sm" variant="ghost" icon={Pencil}
                  onClick={() => setModalPlan(p)}>
                  Edit
                </Button>
              </div>
            </div>
          ))}
        </div>
      )}

      {modalPlan !== null && (
        <PlanModal plan={modalPlan} onClose={() => setModalPlan(null)} />
      )}
      {drawerPlan && (
        <SubscribersDrawer plan={drawerPlan} onClose={() => setDrawerPlan(null)} />
      )}
    </div>
  )
}
