-- Conferência da bronze, antes da silver.
-- Uma linha por tabela: quantas linhas esperávamos (seed 42) e quantas chegaram.
-- Se alguma divergir, raise_error() derruba a tarefa dizendo qual tabela e onde olhar.
-- (bronze.tb_feriados fica de fora: ela cresce a cada execução da API.)
-- Atenção: a sql_task corta o arquivo em todo ponto e vírgula, por isso um único comando.

WITH contagem AS (
  SELECT 'projetos'            AS tabela, 60    AS esperado, COUNT(*) AS obtido FROM lakehouse_vertice.bronze.projetos
  UNION ALL SELECT 'status_semanal',      3911,  COUNT(*) FROM lakehouse_vertice.bronze.status_semanal
  UNION ALL SELECT 'excel_tarefas',       1663,  COUNT(*) FROM lakehouse_vertice.bronze.excel_tarefas
  UNION ALL SELECT 'clickup_tarefas',     2119,  COUNT(*) FROM lakehouse_vertice.bronze.clickup_tarefas
  UNION ALL SELECT 'msproject_tarefas',   1260,  COUNT(*) FROM lakehouse_vertice.bronze.msproject_tarefas
  UNION ALL SELECT 'colaboradores',       523,   COUNT(*) FROM lakehouse_vertice.bronze.colaboradores
  UNION ALL SELECT 'apontamentos',        30883, COUNT(*) FROM lakehouse_vertice.bronze.apontamentos
  UNION ALL SELECT 'custos',              23640, COUNT(*) FROM lakehouse_vertice.bronze.custos
  UNION ALL SELECT 'entregas_fornecedor', 640,   COUNT(*) FROM lakehouse_vertice.bronze.entregas_fornecedor
)
SELECT
  tabela,
  esperado,
  obtido,
  CASE
    WHEN obtido = esperado THEN 'ok'
    ELSE raise_error(concat(
      'bronze.', tabela, ' divergiu: esperado ', esperado, ', obtido ', obtido,
      '. Olhe a saída da tarefa ingestao_data_lake (download do data lake e read_files).'))
  END AS resultado
FROM contagem
ORDER BY tabela
