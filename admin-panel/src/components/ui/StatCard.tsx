import { type LucideIcon } from 'lucide-react'
import { cn } from '@/lib/utils'

interface Props {
  label:      string
  value:      string | number
  sub?:       string
  icon:       LucideIcon
  iconColor?: string
  iconBg?:    string
  trend?:     'up' | 'down' | 'neutral'
  loading?:   boolean
}

export default function StatCard({
  label, value, sub, icon: Icon, iconColor = 'text-indigo-400',
  iconBg = 'bg-indigo-600/15', loading = false,
}: Props) {
  return (
    <div className="rounded-xl border border-gray-800 bg-gray-900 p-5">
      <div className="flex items-start justify-between">
        <div className="space-y-1">
          <p className="text-xs font-semibold uppercase tracking-wider text-gray-500">
            {label}
          </p>
          {loading ? (
            <div className="h-7 w-24 animate-pulse rounded-md bg-gray-800" />
          ) : (
            <p className="text-2xl font-bold text-white">{value}</p>
          )}
          {sub && !loading && (
            <p className="text-xs text-gray-500">{sub}</p>
          )}
        </div>
        <div className={cn('flex h-10 w-10 items-center justify-center rounded-xl', iconBg)}>
          <Icon className={cn('h-5 w-5', iconColor)} />
        </div>
      </div>
    </div>
  )
}
