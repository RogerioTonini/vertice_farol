-- silver.projetos · o cadastro do PMO
-- É o de-para da integração: ferramenta + codigo_ferramenta dizem onde mora o cronograma de cada projeto.
-- Sujeiras tratadas aqui (seção 3 do CLAUDE.md): #1 data em dois formatos, #2 ferramenta de 8 jeitos,
-- #3 código da ferramenta vazio (vira NULL, e as tarefas casam por outro caminho).

CREATE OR REFRESH MATERIALIZED VIEW projetos (
  CONSTRAINT data_inicio_valida    EXPECT (data_inicio IS NOT NULL)                         ON VIOLATION FAIL UPDATE,
  CONSTRAINT ferramenta_conhecida  EXPECT (ferramenta IN ('excel', 'clickup', 'msproject')) ON VIOLATION FAIL UPDATE
)
COMMENT 'Cadastro dos 60 projetos da Vértice (PMO): cliente, segmento, contrato, orçamento, datas, gerente e a ferramenta onde o cronograma é controlado (excel, clickup ou msproject). É o de-para que liga as tarefas das três ferramentas ao projeto.'
AS
SELECT
  projeto_id,
  nome_projeto,
  cliente,
  segmento,
  tipo_projeto,

  -- #2: 'ClickUp', 'Clickup', 'Excel', 'excel', 'Planilha', 'MS Project', 'Project', 'msproject' → 3 valores
  CASE
    WHEN lower(ferramenta) LIKE '%click%'                                    THEN 'clickup'
    WHEN lower(ferramenta) LIKE '%project%'                                  THEN 'msproject'
    WHEN lower(ferramenta) LIKE '%excel%' OR lower(ferramenta) LIKE '%planilha%' THEN 'excel'
  END                                               AS ferramenta,
  ferramenta                                        AS ferramenta_como_veio,

  -- #3: código vazio vira NULL (PRJ-009 no ClickUp e PRJ-012 no Excel)
  nullif(trim(codigo_ferramenta), '')               AS codigo_ferramenta,

  CAST(valor_contrato  AS DECIMAL(18, 2))           AS valor_contrato,
  CAST(orcamento_custo AS DECIMAL(18, 2))           AS orcamento_custo,

  -- #1: 'yyyy-MM-dd' ou 'dd/MM/yyyy'
  coalesce(try_to_date(data_inicio, 'yyyy-MM-dd'),
           try_to_date(data_inicio, 'dd/MM/yyyy'))  AS data_inicio,
  coalesce(try_to_date(data_fim_baseline, 'yyyy-MM-dd'),
           try_to_date(data_fim_baseline, 'dd/MM/yyyy')) AS data_fim_baseline,

  status,
  gerente_projeto
FROM lakehouse_vertice.bronze.projetos;
