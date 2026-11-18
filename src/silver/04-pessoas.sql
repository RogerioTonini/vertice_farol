-- silver.colaboradores e silver.apontamentos
-- Sujeira tratada aqui: #16 pessoa cadastrada duas vezes.


-- O cadastro das 520 pessoas.
CREATE OR REFRESH MATERIALIZED VIEW colaboradores
COMMENT 'Cadastro das 520 pessoas da Vértice: papel (tech_lead, dev, qa, sre...), senioridade, custo por hora, admissão e desligamento. Uma linha por colaborador_id.'
AS
WITH numerado AS (
  -- #16: COL0102, COL0257 e COL0433 aparecem duas vezes, a cópia com nome e papel em CAIXA ALTA.
  -- Ficamos com o cadastro cujo papel está em minúsculas.
  SELECT
    *,
    row_number() OVER (
      PARTITION BY colaborador_id
      ORDER BY CASE WHEN papel = lower(papel) THEN 0 ELSE 1 END
    ) AS ordem
  FROM lakehouse_vertice.bronze.colaboradores
)
SELECT
  colaborador_id,
  nome,
  papel,
  senioridade,
  CAST(custo_hora AS DECIMAL(10, 2))                AS custo_hora,
  try_to_date(data_admissao, 'yyyy-MM-dd')          AS data_admissao,
  try_to_date(nullif(trim(data_desligamento), ''), 'yyyy-MM-dd') AS data_desligamento
FROM numerado
WHERE ordem = 1;


-- O timesheet semanal.
CREATE OR REFRESH MATERIALIZED VIEW apontamentos
COMMENT 'Timesheet semanal: horas disponíveis e horas apontadas por pessoa e projeto. semana_inicio é a segunda-feira e semana é a sexta da mesma semana (o mesmo dia do status semanal).'
AS
SELECT
  colaborador_id,
  projeto_id,
  to_date(semana_inicio)                            AS semana_inicio,
  date_add(to_date(semana_inicio), 4)               AS semana,
  CAST(horas_disponiveis AS DOUBLE)                 AS horas_disponiveis,
  CAST(horas_apontadas   AS DOUBLE)                 AS horas_apontadas
FROM lakehouse_vertice.bronze.apontamentos;
