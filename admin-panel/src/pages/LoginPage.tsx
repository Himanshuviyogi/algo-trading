import { useEffect, useState } from 'react'
import { useNavigate, useLocation } from 'react-router-dom'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Eye, EyeOff, TrendingUp, AlertCircle } from 'lucide-react'
import { useAuth } from '@/contexts/AuthContext'
import { cn } from '@/lib/utils'

// ── Form schema ───────────────────────────────────────────────────────────────

const schema = z.object({
  email:    z.string().email('Enter a valid email'),
  password: z.string().min(6, 'Password must be at least 6 characters'),
})
type FormValues = z.infer<typeof schema>

// ── Page ──────────────────────────────────────────────────────────────────────

export default function LoginPage() {
  const { user, loading, login, error, clearError } = useAuth()
  const navigate  = useNavigate()
  const location  = useLocation()
  const from      = (location.state as { from?: Location })?.from?.pathname ?? '/dashboard'

  const [showPw, setShowPw]       = useState(false)
  const [submitting, setSubmitting] = useState(false)

  const { register, handleSubmit, formState: { errors } } = useForm<FormValues>({
    resolver: zodResolver(schema),
  })

  // Redirect if already signed in
  useEffect(() => {
    if (!loading && user) navigate(from, { replace: true })
  }, [user, loading, from, navigate])

  const onSubmit = async (values: FormValues) => {
    setSubmitting(true)
    clearError()
    try {
      await login(values.email, values.password)
      navigate(from, { replace: true })
    } catch {
      // error is set by AuthContext
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="flex min-h-screen items-center justify-center bg-gray-950 px-4">
      {/* Card */}
      <div className="w-full max-w-md rounded-2xl border border-gray-800 bg-gray-900 p-8 shadow-2xl">

        {/* Logo */}
        <div className="mb-8 flex flex-col items-center gap-3">
          <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-indigo-600 shadow-lg">
            <TrendingUp className="h-6 w-6 text-white" strokeWidth={2.5} />
          </div>
          <div className="text-center">
            <h1 className="text-xl font-bold tracking-tight text-white">
              Stockara Admin
            </h1>
            <p className="mt-0.5 text-sm text-gray-400">
              Sign in with your admin account
            </p>
          </div>
        </div>

        {/* Error banner */}
        {error && (
          <div className="mb-4 flex items-start gap-3 rounded-lg border border-red-800 bg-red-950 px-4 py-3 text-sm text-red-300">
            <AlertCircle className="mt-0.5 h-4 w-4 shrink-0" />
            <span>{error}</span>
          </div>
        )}

        {/* Form */}
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          {/* Email */}
          <div className="space-y-1.5">
            <label className="block text-xs font-semibold uppercase tracking-widest text-gray-400">
              Email
            </label>
            <input
              type="email"
              autoComplete="email"
              placeholder="admin@stockara.in"
              {...register('email')}
              className={cn(
                'w-full rounded-lg border bg-gray-800 px-4 py-3 text-sm text-white placeholder-gray-500',
                'focus:outline-none focus:ring-2 focus:ring-indigo-500',
                errors.email ? 'border-red-600' : 'border-gray-700',
              )}
            />
            {errors.email && (
              <p className="text-xs text-red-400">{errors.email.message}</p>
            )}
          </div>

          {/* Password */}
          <div className="space-y-1.5">
            <label className="block text-xs font-semibold uppercase tracking-widest text-gray-400">
              Password
            </label>
            <div className="relative">
              <input
                type={showPw ? 'text' : 'password'}
                autoComplete="current-password"
                placeholder="••••••••"
                {...register('password')}
                className={cn(
                  'w-full rounded-lg border bg-gray-800 px-4 py-3 pr-11 text-sm text-white placeholder-gray-500',
                  'focus:outline-none focus:ring-2 focus:ring-indigo-500',
                  errors.password ? 'border-red-600' : 'border-gray-700',
                )}
              />
              <button
                type="button"
                tabIndex={-1}
                onClick={() => setShowPw(!showPw)}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-gray-400 hover:text-gray-200"
              >
                {showPw ? <EyeOff className="h-4 w-4" /> : <Eye className="h-4 w-4" />}
              </button>
            </div>
            {errors.password && (
              <p className="text-xs text-red-400">{errors.password.message}</p>
            )}
          </div>

          {/* Submit */}
          <button
            type="submit"
            disabled={submitting}
            className={cn(
              'mt-2 w-full rounded-lg bg-indigo-600 py-3 text-sm font-bold text-white',
              'transition hover:bg-indigo-500 focus:outline-none focus:ring-2 focus:ring-indigo-400',
              'disabled:cursor-not-allowed disabled:opacity-50',
            )}
          >
            {submitting ? (
              <span className="flex items-center justify-center gap-2">
                <span className="h-4 w-4 animate-spin rounded-full border-2 border-white border-t-transparent" />
                Signing in…
              </span>
            ) : (
              'Sign in'
            )}
          </button>
        </form>

        {/* Note */}
        <p className="mt-6 text-center text-xs text-gray-600">
          Admin access only. Contact the owner to request access.
        </p>
      </div>
    </div>
  )
}
