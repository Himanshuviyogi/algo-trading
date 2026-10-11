/**
 * useSignals — TanStack Query hooks for algo_signals collection.
 *
 * All writes go directly to Firestore using the Firebase Web SDK.
 * The admin user must have the { admin: true } custom claim and Firestore
 * rules must allow admin writes to algo_signals.
 */

import {
  collection, query, orderBy, limit, onSnapshot,
  addDoc, updateDoc, deleteDoc, doc,
  serverTimestamp, type QuerySnapshot, type DocumentData,
} from 'firebase/firestore'
import {
  useMutation,
} from '@tanstack/react-query'
import { useEffect, useState } from 'react'
import { db } from '@/lib/firebase'

// ── Types ─────────────────────────────────────────────────────────────────────

export interface AlgoSignal {
  id:           string        // Firestore doc id
  title?:       string
  status:       string        // 'live' | 'closed' | 'expired'
  is_published: boolean
  auto_execute: boolean
  plan_ids:     string[]
  category:     string        // 'stocks' | 'options' | 'futures' | 'commodity'
  type:         string        // 'intraday' | 'short_term' | 'medium_term'
  source:       string        // 'admin' | 'user'
  body?:        string
  confidence?:  string
  tags?:        string[]
  posted_at?:   unknown
  stock?: {
    name?:     string
    symbol?:   string
    exchange?: string
  }
  trade?: {
    action?:       string   // BUY | SELL
    entry_price?:  number
    order_type?:   string   // LIMIT | MARKET | SL | SL-M
    product_type?: string   // CNC | MIS | NRML
    validity?:     string   // DAY | IOC
    lot_size?:     number | null
    option_type?:  string | null
    strike_price?: number | null
    expiry_date?:  string | null
  }
  analysis?: {
    target?:   number
    target2?:  number | null
    stoploss?: number
    duration?: string
  }
  performance?: {
    gain_so_far?:    number
    potential_left?: number
  }
}

export type SignalFormValues = Omit<AlgoSignal, 'id' | 'posted_at'>

// ── Real-time listener hook ───────────────────────────────────────────────────

/** Subscribes to the last 100 algo_signals ordered by posted_at desc. */
export function useSignalsLive(): { signals: AlgoSignal[]; loading: boolean; error: string | null } {
  const [signals, setSignals] = useState<AlgoSignal[]>([])
  const [loading, setLoading] = useState(true)
  const [error,   setError]   = useState<string | null>(null)

  useEffect(() => {
    const q = query(
      collection(db, 'algo_signals'),
      orderBy('posted_at', 'desc'),
      limit(100),
    )

    const unsub = onSnapshot(
      q,
      (snap: QuerySnapshot<DocumentData>) => {
        setSignals(snap.docs.map(d => ({ id: d.id, ...d.data() } as AlgoSignal)))
        setLoading(false)
      },
      (err) => {
        setError(err.message)
        setLoading(false)
      },
    )

    return unsub
  }, [])

  return { signals, loading, error }
}

// ── Write mutations ───────────────────────────────────────────────────────────

/** Create a new signal document. */
export function useCreateSignal() {
  return useMutation({
    mutationFn: async (values: SignalFormValues) => {
      await addDoc(collection(db, 'algo_signals'), {
        ...values,
        posted_at:  serverTimestamp(),
        seed_id:    null,
      })
    },
  })
}

/** Update an existing signal document (partial merge). */
export function useUpdateSignal() {
  return useMutation({
    mutationFn: async ({ id, values }: { id: string; values: Partial<AlgoSignal> }) => {
      const { id: _id, posted_at: _pt, ...rest } = values as AlgoSignal
      await updateDoc(doc(db, 'algo_signals', id), rest)
    },
  })
}

/** Toggle is_published on a signal. Triggers onAlgoSignalWritten Cloud Function. */
export function usePublishSignal() {
  return useMutation({
    mutationFn: async ({ id, publish }: { id: string; publish: boolean }) => {
      await updateDoc(doc(db, 'algo_signals', id), {
        is_published: publish,
        status:       publish ? 'live' : 'live',  // keeps status live regardless
      })
    },
  })
}

/** Delete a signal document. */
export function useDeleteSignal() {
  return useMutation({
    mutationFn: async (id: string) => {
      await deleteDoc(doc(db, 'algo_signals', id))
    },
  })
}
