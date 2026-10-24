import { formatearUnidad } from '../../utils/unitHelpers'
import { ChefHat, Info, Utensils } from 'lucide-react'
import type { ReactNode } from 'react'
import type { Consulta } from './service'

export function RecipeCards({ queries, fallback }: { queries: Consulta[]; fallback: ReactNode }) {
  // Only actual recipe records from the authorized query, never example data.
  const query = queries.findLast(q => q.recurso === 'recetas')
  if (!query || !query.registros.length || query.registros.length > 3) return <>{fallback}</>
  return <>{query.registros.map((recipe, index) => <section className="assistant-recipe" key={String(recipe.id_receta ?? index)}>
    <header><ChefHat size={22} /><div><h3>{String(recipe.item_carta ?? 'Receta')}</h3>
      <p>Ingredientes por presentación · {String(recipe.contenido ?? '')} {formatearUnidad(recipe.unidad_presentacion)}</p></div></header>
    <ul>{Array.isArray(recipe.componentes) && recipe.componentes.map((item: Record<string, unknown>, i: number) =>
      <li key={i}><span className="assistant-ingredient-icon"><Utensils size={16} /></span>
        <span>{String(item.nombre_componente ?? item.producto_nombre ?? item.subproducto_nombre ?? 'Ingrediente')}</span>
        <strong>{typeof item.cantidad === 'number' ? item.cantidad.toLocaleString('es-PE', { maximumFractionDigits: 3 }) : String(item.cantidad ?? '')} {formatearUnidad(item.unidad)}</strong></li>)}</ul>
    <footer><Info size={18} /><span>{String(recipe.instrucciones || 'Instrucciones de preparación pendientes de registrar.')}</span></footer>
  </section>)}</>
}
