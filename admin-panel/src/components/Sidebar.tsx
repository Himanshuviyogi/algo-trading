import { NavLink } from 'react-router-dom'
import {
  LayoutDashboard,
  Radio,
  Users,
  ShieldCheck,
  BookOpen,
  Layers,
  Server,
  TrendingUp,
  X,
} from 'lucide-react'
import { cn } from '@/lib/utils'

// ── Nav items ─────────────────────────────────────────────────────────────────

interface NavItem {
  label:    string
  to:       string
  icon:     React.ElementType
  badge?:   string
  phase?:   number   // 2+ = coming soon (grayed out)
}

const NAV_ITEMS: NavItem[] = [
  { label: 'Dashboard',     to: '/dashboard', icon: LayoutDashboard },
  { label: 'Signals',       to: '/signals',   icon: Radio },
  { label: 'Users',         to: '/users',     icon: Users },
  { label: 'Subscriptions', to: '/subs',      icon: BookOpen },
  { label: 'Risk Controls', to: '/risk',      icon: ShieldCheck },
  { label: 'Orders',        to: '/orders',    icon: Layers },
  { label: 'Positions',     to: '/positions', icon: TrendingUp },
  // Phase 3
  { label: 'Price Server',  to: '/server',    icon: Server, phase: 2 },
]

// ── Component ─────────────────────────────────────────────────────────────────

interface Props {
  open:    boolean
  onClose: () => void
}

export default function Sidebar({ open, onClose }: Props) {
  return (
    <>
      {/* Mobile overlay */}
      {open && (
        <div
          className="fixed inset-0 z-20 bg-black/60 lg:hidden"
          onClick={onClose}
        />
      )}

      {/* Sidebar panel */}
      <aside
        className={cn(
          'fixed inset-y-0 left-0 z-30 flex flex-col border-r border-gray-800 bg-gray-900',
          'transition-transform duration-200 ease-in-out',
          'lg:relative lg:translate-x-0',
          open ? 'w-60 translate-x-0' : 'w-0 -translate-x-full lg:w-16',
        )}
      >
        {/* Logo strip */}
        <div className="flex h-14 shrink-0 items-center justify-between border-b border-gray-800 px-4">
          {open && (
            <div className="flex items-center gap-2.5">
              <div className="flex h-7 w-7 items-center justify-center rounded-lg bg-indigo-600">
                <TrendingUp className="h-4 w-4 text-white" strokeWidth={2.5} />
              </div>
              <span className="text-sm font-bold tracking-tight text-white">
                Stockara<span className="text-indigo-400"> Admin</span>
              </span>
            </div>
          )}
          <button
            onClick={onClose}
            className="rounded-md p-1 text-gray-400 hover:text-white lg:hidden"
          >
            <X className="h-5 w-5" />
          </button>
        </div>

        {/* Nav links */}
        <nav className="flex-1 overflow-y-auto py-4">
          {NAV_ITEMS.map((item) => {
            const isPhase2 = (item.phase ?? 1) >= 2
            const Icon = item.icon

            if (isPhase2) {
              // Disabled future item
              return (
                <div
                  key={item.label}
                  className={cn(
                    'flex items-center gap-3 px-4 py-2.5 text-sm text-gray-600 cursor-not-allowed select-none',
                    !open && 'justify-center px-0',
                  )}
                  title={open ? undefined : item.label}
                >
                  <Icon className="h-4 w-4 shrink-0" />
                  {open && (
                    <span className="flex-1 truncate">{item.label}</span>
                  )}
                  {open && (
                    <span className="rounded bg-gray-800 px-1.5 py-0.5 text-[9px] font-bold uppercase tracking-wider text-gray-500">
                      Soon
                    </span>
                  )}
                </div>
              )
            }

            return (
              <NavLink
                key={item.label}
                to={item.to}
                title={!open ? item.label : undefined}
                className={({ isActive }) =>
                  cn(
                    'group flex items-center gap-3 px-4 py-2.5 text-sm font-medium transition-colors',
                    'hover:bg-gray-800 hover:text-white',
                    isActive
                      ? 'bg-indigo-600/15 text-indigo-400 border-r-2 border-indigo-500'
                      : 'text-gray-400',
                    !open && 'justify-center px-0',
                  )
                }
              >
                <Icon className="h-4 w-4 shrink-0" />
                {open && <span className="flex-1 truncate">{item.label}</span>}
                {open && item.badge && (
                  <span className="rounded-full bg-indigo-600 px-1.5 py-0.5 text-[9px] font-bold text-white">
                    {item.badge}
                  </span>
                )}
              </NavLink>
            )
          })}
        </nav>

        {/* Bottom version tag */}
        {open && (
          <div className="border-t border-gray-800 px-4 py-3 text-[11px] text-gray-600">
            Phase 1 · algo-stockara
          </div>
        )}
      </aside>
    </>
  )
}
