import { cn } from '@/lib/utils'
import { type LucideIcon } from 'lucide-react'

type Variant = 'primary' | 'secondary' | 'danger' | 'ghost' | 'outline'
type Size    = 'sm' | 'md' | 'lg'

const variantStyles: Record<Variant, string> = {
  primary:   'bg-indigo-600 text-white hover:bg-indigo-500 border-transparent',
  secondary: 'bg-gray-700 text-white hover:bg-gray-600 border-transparent',
  danger:    'bg-red-700 text-white hover:bg-red-600 border-transparent',
  ghost:     'bg-transparent text-gray-300 hover:bg-gray-800 border-transparent',
  outline:   'bg-transparent text-gray-300 hover:bg-gray-800 border-gray-700',
}

const sizeStyles: Record<Size, string> = {
  sm:  'px-3 py-1.5 text-xs gap-1.5',
  md:  'px-4 py-2 text-sm gap-2',
  lg:  'px-5 py-2.5 text-sm gap-2',
}

interface Props extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?:  Variant
  size?:     Size
  icon?:     LucideIcon
  loading?:  boolean
  children?: React.ReactNode
}

export default function Button({
  variant = 'primary', size = 'md', icon: Icon, loading = false,
  children, className, disabled, ...rest
}: Props) {
  return (
    <button
      disabled={disabled || loading}
      className={cn(
        'inline-flex items-center justify-center rounded-lg border font-semibold',
        'transition-colors focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 focus:ring-offset-gray-900',
        'disabled:cursor-not-allowed disabled:opacity-50',
        variantStyles[variant],
        sizeStyles[size],
        className,
      )}
      {...rest}
    >
      {loading ? (
        <span className="h-4 w-4 animate-spin rounded-full border-2 border-current border-t-transparent" />
      ) : Icon ? (
        <Icon className="h-4 w-4 shrink-0" />
      ) : null}
      {children}
    </button>
  )
}
