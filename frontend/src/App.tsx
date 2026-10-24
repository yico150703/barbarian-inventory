import { AssistantPage } from './features/asistenteIA/AssistantPage'
import { SalonLayoutPage } from './pages/SalonLayoutPage'
import { SalonOrderPage } from './pages/SalonOrderPage'
import { SalonPaymentPage } from './features/salonPayments/SalonPaymentPage'
import { SalonPage } from './pages/SalonPage'
import { ActivityPage } from './pages/ActivityPage'
import { MovementTrackingPage } from './pages/MovementTrackingPage'
import {
  Navigate,
  Route,
  Routes,
} from 'react-router-dom'
import { SuppliersPage } from './pages/SuppliersPage'
import { ProtectedRoute } from './components/ProtectedRoute'
import { MainLayout } from './components/layout/MainLayout'
import { ProductsPage } from './pages/ProductsPage'
import { HomePage } from './pages/HomePage'
import { OperationalPage } from './features/inventoryOperations/OperationalPage'
import LoginPage from './pages/LoginPage'
import { ModulePlaceholderPage } from './pages/ModulePlaceholderPage'
import { StockPage } from './pages/StockPage'
import { StockLimitsPage } from './pages/StockLimitsPage'
import {
  ProductCategoriesPage,
} from './pages/ProductCategoriesPage'
import {
  MenuCategoriesPage,
} from './pages/MenuCategoriesPage'

import {
  SubproductsPage,
} from './pages/SubproductsPage'

import {
  SalesPresentationsPage,
} from './pages/SalesPresentationsPage'
import {
  TablewarePage,
} from './pages/TablewarePage'

import {
  PromotionsPage,
} from './pages/PromotionsPage'


import { RegisterMovementPage } from './pages/RegisterMovementPage'

import { PendingReceiptsPage } from './pages/PendingReceiptsPage'

import { PurchaseOrderPage } from './pages/PurchaseOrderPage'

import { UsersPage } from './pages/UsersPage'
import { StoresPage } from './pages/StoresPage'
import { RecipesPage } from './pages/RecipesPage'

import { PurchaseOrderHistoryPage } from './pages/PurchaseOrderHistoryPage'
import { ReceptionHistoryPage } from './pages/ReceptionHistoryPage'

function App() {
  return (
    <Routes>
      <Route path="/salon" element={<SalonPage />} />
      <Route path="/salon/mesa/:mesa" element={<SalonOrderPage />} />
      <Route path="/salon/mesa/:mesa/pagar" element={<SalonPaymentPage />} />
      <Route path="/salon/comprobante/:id" element={<SalonPaymentPage />} />
      <Route
        path="/"
        element={<Navigate to="/login" replace />}
      />

      <Route
        path="/login"
        element={<LoginPage />}
      />

      <Route
        path="/home"
        element={
          <ProtectedRoute>
            <MainLayout />
          </ProtectedRoute>
        }
      >
        <Route
          index
          element={<HomePage />}
        />

        <Route
          path="stock"
          element={<StockPage />}
        />
        <Route path="asistente-ia" element={<AssistantPage />} />
        <Route path="tiendas" element={<StoresPage />} />
        <Route path="opciones-salon" element={<SalonLayoutPage />} />
        <Route path="limites-stock" element={<StockLimitsPage />} />

        <Route
          path="productos"
          element={<ProductsPage />}
        />

        <Route
          path="categorias-productos"
          element={<ProductCategoriesPage />}
        />

        <Route
          path="proveedores"
          element={<SuppliersPage />}
        />

        <Route
          path="carta/categorias"
          element={<MenuCategoriesPage />}
        />

        <Route
          path="carta/presentaciones"
          element={<SalesPresentationsPage />}
        />

        <Route
          path="subproductos"
          element={<SubproductsPage />}
        />

        <Route
          path="grupos-salsa"
          element={<Navigate to="/home/recetas" replace />}
        />

        <Route
          path="recetas"
          element={<RecipesPage />}
        />

        <Route
          path="carta/menajes"
          element={<TablewarePage />}
        />

        <Route
          path="inventarios/realizar"
          element={<Navigate to="/home/inventarios/conteos" replace />}
        />

        <Route
          path="promociones"
          element={<PromotionsPage />}
        />

        <Route
          path="inventarios/revisar"
          element={<Navigate to="/home/inventarios/conteos" replace />}
        />

        <Route
          path="recepciones/pendientes"
          element={<PendingReceiptsPage />}
        />
        <Route path="inventarios/dia" element={<OperationalPage section="day" />} />
        <Route path="inventarios/mix" element={<OperationalPage section="mix" />} />
        <Route path="inventarios/conteos" element={<OperationalPage section="counts" />} />

        <Route
          path="movimientos/seguimiento" element={<MovementTrackingPage />} />
        <Route
          path="movimientos/registrar"
          element={<RegisterMovementPage />}
        />

        <Route
          path="ordenes-compra/crear"
          element={<PurchaseOrderPage />}
        />

        <Route
          path="actividades" element={<ActivityPage />} />
        <Route
          path="usuarios"
          element={<UsersPage />}
        />

        <Route
          path="ordenes-compra/historial"
          element={<PurchaseOrderHistoryPage />}
        />

        <Route
          path="recepciones/historial"
          element={<ReceptionHistoryPage />}
        />

        <Route
          path="*"
          element={<ModulePlaceholderPage />}
        />
      </Route>

      <Route
        path="*"
        element={<Navigate to="/home" replace />}
      />
    </Routes>
  )
}

export default App
