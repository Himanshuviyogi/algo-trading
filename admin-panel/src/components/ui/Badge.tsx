import { cn } from '@/lib/utils'

type Variant = 'default' | 'success' | 'warning' | 'danger' | 'info' | 'muted'

const styles: Record<Variant, string> = {
  default: 'bg-indigo-600/15 text-indigo-400 border-indigo-600/30',
  success: 'bg-emerald-600/15 text-emerald-400 border-emerald-600/30',
  warning: 'bg-amber-600/15 text-amber-400 border-amber-600/30',
  danger:  'bg-red-600/15 text-red-400 border-red-600/30',
  info:    'bg-sky-600/15 text-sky-400 border-sky-600/30',
  muted:   'bg-gray-700/50 text-gray-400 border-gray-700',
}

interface Props {
  variant?: Variant
  children: React.ReactNode
  className?: string
}

export default function Badge({ variant = 'default', children, className }: Props) {
  return (
    <span
      className={cn(
        'inline-flex items-center rounded-full border px-2 py-0.5 text-[10px] font-bold uppercase tracking-wider',
        styles[variant],
        className,
      )}
    >
      {children}
    </span>
  )
}
