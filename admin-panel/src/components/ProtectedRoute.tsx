import { Navigate, useLocation } from 'react-router-dom'
import { useAuth } from '@/contexts/AuthContext'

interface Props {
  children: React.ReactNode
  /** If true, also requires the admin custom claim. Default: true */
  requireAdmin?: boolean
}

/**
 * Wraps any route that requires authentication.
 * Redirects unauthenticated users to /login.
 * Redirects non-admin users to /not-authorized.
 */
export default function ProtectedRoute({ children, requireAdmin = true }: Props) {
  const { user, loading, isAdmin } = useAuth()
  const location = useLocation()

  if (loading) {
    return (
      <div className="flex h-screen items-center justify-center bg-gray-950">
        <div className="flex flex-col items-center gap-3">
          <div className="h-8 w-8 animate-spin rounded-full border-4 border-indigo-500 border-t-transparent" />
          <span className="text-sm text-gray-400">Loading session…</span>
        </div>
      </div>
    )
  }

  if (!user) {
    return <Navigate to="/login" state={{ from: location }} replace />
  }

  if (requireAdmin && !isAdmin) {
    return <Navigate to="/not-authorized" replace />
  }

  return <>{children}</>
}
