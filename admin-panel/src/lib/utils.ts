import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

/** Merges Tailwind classes safely. */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

/** Format a number as Indian rupees. */
export function fmtRs(value: number, decimals = 0): string {
  const abs = Math.abs(value)
  let formatted: string
  if (abs >= 1_00_000) formatted = `${(value / 1_00_000).toFixed(1)}L`
  else if (abs >= 1_000) formatted = `${(value / 1_000).toFixed(1)}K`
  else formatted = value.toFixed(decimals)
  return `₹${formatted}`
}

/** Format a Firestore Timestamp or JS Date. */
export function fmtDate(ts: { toDate?: () => Date } | Date | string | null | undefined): string {
  if (!ts) return '—'
  let d: Date
  if (ts instanceof Date) d = ts
  else if (typeof ts === 'string') d = new Date(ts)
  else if (typeof (ts as any).toDate === 'function') d = (ts as any).toDate()
  else return '—'
  return d.toLocaleString('en-IN', {
    day:    '2-digit',
    month:  'short',
    year:   'numeric',
    hour:   '2-digit',
    minute: '2-digit',
    hour12: true,
  })
}

/** Returns green / red / yellow class based on sign. */
export function pnlColor(value: number): string {
  if (value > 0) return 'text-emerald-600'
  if (value < 0) return 'text-red-600'
  return 'text-gray-500'
}
