export interface UnidadMedida {
  codigo: string
  valor: string
  nombre: string
  simbolo: string
  dimension: 'MASA' | 'VOLUMEN' | 'CONTEO'
  codigo_unece: string | null
  codigo_base: string
  factor_a_base: string
  estandar: 'UNECE Rec. 20' | 'LOCAL'
}

export interface MedidaConUnidad {
  unidad_medida?: UnidadMedida
  unidad_presentacion_medida?: UnidadMedida
}
