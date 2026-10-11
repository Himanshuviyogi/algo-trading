import { Menu, LogOut, User } from 'lucide-react'
import { useNavigate } from 'react-router-dom'
import { useAuth } from '@/contexts/AuthContext'
import { cn } from '@/lib/utils'

interface Props {
  onMenuClick: () => void
}

export default function Topbar({ onMenuClick }: Props) {
  const { user, logout } = useAuth()
  const navigate = useNavigate()

  const handleLogout = async () => {
    await logout()
    navigate('/login')
  }

  return (
    <header className="flex h-14 shrink-0 items-center justify-between border-b border-gray-800 bg-gray-900 px-4">
      {/* Left — hamburger */}
      <button
        onClick={onMenuClick}
        className="rounded-md p-1.5 text-gray-400 hover:bg-gray-800 hover:text-white"
        aria-label="Toggle sidebar"
      >
        <Menu className="h-5 w-5" />
      </button>

      {/* Right — user info + logout */}
      <div className="flex items-center gap-3">
        {/* Admin badge */}
        <span className="hidden rounded bg-indigo-600/20 px-2 py-0.5 text-[11px] font-bold uppercase tracking-wider text-indigo-400 sm:block">
          Admin
        </span>

        {/* User email */}
        <div className="flex items-center gap-2 rounded-lg border border-gray-800 bg-gray-800/50 px-3 py-1.5">
          <User className="h-3.5 w-3.5 text-gray-400" />
          <span className="max-w-[180px] truncate text-xs text-gray-300">
            {user?.email ?? '—'}
          </span>
        </div>

        {/* Logout */}
        <button
          onClick={handleLogout}
          className={cn(
            'flex items-center gap-1.5 rounded-lg border border-gray-700 px-3 py-1.5',
            'text-xs text-gray-400 hover:border-red-800 hover:bg-red-950 hover:text-red-300',
            'transition-colors',
          )}
        >
          <LogOut className="h-3.5 w-3.5" />
          <span className="hidden sm:block">Sign out</span>
        </button>
      </div>
    </header>
  )
}
