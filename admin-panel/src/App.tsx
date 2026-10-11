import { Routes, Route, Navigate } from 'react-router-dom'
import ProtectedRoute from '@/components/ProtectedRoute'
import Layout from '@/components/Layout'
import LoginPage from '@/pages/LoginPage'
import DashboardPage from '@/pages/DashboardPage'
import SignalsPage from '@/pages/SignalsPage'
import UsersPage from '@/pages/UsersPage'
import SubscriptionsPage from '@/pages/SubscriptionsPage'
import RiskControlsPage from '@/pages/RiskControlsPage'
import OrdersPage from '@/pages/OrdersPage'
import PositionsPage from '@/pages/PositionsPage'
import NotAuthorizedPage from '@/pages/NotAuthorizedPage'

export default function App() {
  return (
    <Routes>
      {/* Public */}
      <Route path="/login"          element={<LoginPage />} />
      <Route path="/not-authorized" element={<NotAuthorizedPage />} />

      {/* Protected admin routes — wrapped in sidebar layout */}
      <Route
        path="/"
        element={
          <ProtectedRoute>
            <Layout />
          </ProtectedRoute>
        }
      >
        <Route index                element={<Navigate to="/dashboard" replace />} />
        <Route path="dashboard"     element={<DashboardPage />} />
        <Route path="signals"       element={<SignalsPage />} />
        <Route path="users"         element={<UsersPage />} />
        <Route path="subs"          element={<SubscriptionsPage />} />
        <Route path="risk"          element={<RiskControlsPage />} />
        <Route path="orders"        element={<OrdersPage />} />
        <Route path="positions"     element={<PositionsPage />} />
        {/* Price Server — coming soon */}
        {/* <Route path="server"     element={<PriceServerPage />} /> */}
      </Route>

      {/* Catch-all */}
      <Route path="*" element={<Navigate to="/dashboard" replace />} />
    </Routes>
  )
}
