-- silver.tarefas · AS TRÊS FERRAMENTAS VIRAM UMA
-- Cada ferramenta vira uma visão temporária com as MESMAS 13 colunas, e a materialized view
-- empilha as três (UNION ALL). É aqui que mora a integração do Projeto Farol.
--
--   projeto_id, ferramenta, id_na_ferramenta, fase, tarefa, responsavel,
--   inicio_baseline, fim_baseline, inicio_real, fim_real, pct_como_veio, horas, status_na_ferramenta
--
-- status_na_ferramenta sai sempre em 3 valores: concluida / a_fazer / em_andamento.
-- O ClickUp traz o status escrito de 12 jeitos. Excel e MS Project não têm status: derivamos do %.


-- ---------------------------------------------------------------------------------------------
-- 1) Excel · 20 planilhas, tudo texto
--    Sujeiras: #3 código vazio, #4 data em texto OU número de série, #5 % em 3 formatos,
--    #6 linha de TOTAL, #7 horas '40h'
-- ---------------------------------------------------------------------------------------------
CREATE TEMPORARY VIEW tarefas_excel AS
WITH limpo AS (
  SELECT
    -- o de-para pelo nome do arquivo e, se não casar (código vazio, ou o arquivo chegou sem acento:
    -- 'Core bancario' × 'Core bancário'), o PRJ-xxx que está no próprio nome do arquivo
    coalesce(p.projeto_id, regexp_extract(e.arquivo, 'PRJ-[0-9]{3}', 0)) AS projeto_id,
    'excel'                                         AS ferramenta,
    CAST(e.id AS STRING)                            AS id_na_ferramenta,
    e.fase,
    e.tarefa,
    e.responsavel,

    -- #4: com '/' é dd/MM/yyyy, senão é o número de série do Excel (dias desde 30/12/1899)
    CASE WHEN e.inicio_previsto  LIKE '%/%' THEN to_date(e.inicio_previsto, 'dd/MM/yyyy')
         ELSE date_add(DATE'1899-12-30', CAST(e.inicio_previsto AS INT)) END  AS inicio_baseline,
    CASE WHEN e.termino_previsto LIKE '%/%' THEN to_date(e.termino_previsto, 'dd/MM/yyyy')
         ELSE date_add(DATE'1899-12-30', CAST(e.termino_previsto AS INT)) END AS fim_baseline,
    CASE WHEN e.inicio_real      LIKE '%/%' THEN to_date(e.inicio_real, 'dd/MM/yyyy')
         ELSE date_add(DATE'1899-12-30', CAST(e.inicio_real AS INT)) END      AS inicio_real,
    CASE WHEN e.termino_real     LIKE '%/%' THEN to_date(e.termino_real, 'dd/MM/yyyy')
         ELSE date_add(DATE'1899-12-30', CAST(e.termino_real AS INT)) END     AS fim_real,

    -- #5: '45%' ou '10,5%' → tira o % e troca a vírgula. Sem '%' (0.45 ou 1) é fração → × 100
    CASE WHEN contains(e.pct_concluido, '%')
         THEN CAST(replace(replace(e.pct_concluido, '%', ''), ',', '.') AS DOUBLE)
         ELSE CAST(replace(e.pct_concluido, ',', '.') AS DOUBLE) * 100
    END                                             AS pct_como_veio,

    -- #7: '40h' → 40
    CAST(trim(replace(e.horas_previstas, 'h', '')) AS DOUBLE) AS horas
  FROM lakehouse_vertice.bronze.excel_tarefas e
  LEFT JOIN projetos p
    ON p.ferramenta = 'excel'
   AND p.codigo_ferramenta = e.arquivo
  -- #6: a última linha de cada planilha é o TOTAL (soma das de cima): fora
  WHERE e.tarefa <> 'TOTAL'
)
SELECT
  projeto_id, ferramenta, id_na_ferramenta, fase, tarefa, responsavel,
  inicio_baseline, fim_baseline, inicio_real, fim_real, pct_como_veio, horas,
  CASE WHEN pct_como_veio >= 100 THEN 'concluida'
       WHEN pct_como_veio  = 0   THEN 'a_fazer'
       ELSE 'em_andamento' END                      AS status_na_ferramenta
FROM limpo;


-- ---------------------------------------------------------------------------------------------
-- 2) ClickUp · 25 listas em JSON
--    Sujeiras: #3 código vazio (casa pelo nome da lista), #8 datas em milissegundos e
--    % / baseline / fase dentro de custom_fields, #9 status escrito de 12 jeitos
-- ---------------------------------------------------------------------------------------------
CREATE TEMPORARY VIEW tarefas_clickup AS
SELECT
  -- o de-para pelo list_id e, se o código faltar no cadastro (PRJ-009), pelo nome da lista
  coalesce(p_codigo.projeto_id, p_nome.projeto_id)  AS projeto_id,
  'clickup'                                         AS ferramenta,
  c.id                                              AS id_na_ferramenta,
  -- custom_fields é uma lista de {name, type, value}: filtramos pelo nome e pegamos o 1º
  -- (try_element_at devolve NULL se o campo não existir, em vez de quebrar)
  try_element_at(filter(c.custom_fields, f -> f.name = 'Fase'), 1).value AS fase,
  c.name                                            AS tarefa,
  try_element_at(c.assignees, 1).username           AS responsavel,

  -- #8: datas em milissegundos desde 1970
  to_date(timestamp_millis(CAST(try_element_at(filter(c.custom_fields, f -> f.name = 'Início baseline'), 1).value AS BIGINT))) AS inicio_baseline,
  to_date(timestamp_millis(CAST(try_element_at(filter(c.custom_fields, f -> f.name = 'Fim baseline'), 1).value AS BIGINT)))    AS fim_baseline,
  to_date(timestamp_millis(CAST(c.start_date AS BIGINT)))  AS inicio_real,
  to_date(timestamp_millis(CAST(c.date_done  AS BIGINT)))  AS fim_real,

  CAST(try_element_at(filter(c.custom_fields, f -> f.name = 'Progresso (%)'), 1).value AS DOUBLE) AS pct_como_veio,

  -- time_estimate vem em milissegundos: ÷ 3.600.000 = horas
  c.time_estimate / 3600000.0                       AS horas,

  -- #9: 12 grafias → 3 valores
  CASE
    WHEN lower(trim(c.status.status)) IN ('done', 'closed', 'concluído', 'concluido')            THEN 'concluida'
    WHEN lower(trim(c.status.status)) IN ('to do', 'a fazer', 'backlog')                         THEN 'a_fazer'
    WHEN lower(trim(c.status.status)) IN ('in progress', 'doing', 'em andamento', 'review')      THEN 'em_andamento'
  END                                               AS status_na_ferramenta
FROM lakehouse_vertice.bronze.clickup_tarefas c
LEFT JOIN projetos p_codigo
  ON p_codigo.ferramenta = 'clickup'
 AND p_codigo.codigo_ferramenta = c.list_id
LEFT JOIN projetos p_nome
  ON p_nome.ferramenta = 'clickup'
 AND p_nome.codigo_ferramenta IS NULL
 AND p_nome.nome_projeto = c.list_name;


-- ---------------------------------------------------------------------------------------------
-- 3) MS Project · 15 XML
--    Sujeiras: #10 tarefas-resumo somando as de baixo, #11 a fase não está na tarefa,
--    #12 horas em 'PT40H0M0S'
-- ---------------------------------------------------------------------------------------------
CREATE TEMPORARY VIEW tarefas_msproject AS
WITH com_fase AS (
  -- #11: a fase é a última tarefa-resumo de nível 1 que aparece antes da tarefa (na ordem do UID).
  -- A janela roda sobre TODAS as linhas (inclusive as resumo) e só depois filtramos.
  SELECT
    m.*,
    last_value(CASE WHEN m.OutlineLevel = 1 THEN m.Name END, true)
      OVER (PARTITION BY m.arquivo ORDER BY m.UID)  AS fase
  FROM lakehouse_vertice.bronze.msproject_tarefas m
),
limpo AS (
  SELECT
    p.projeto_id,
    'msproject'                                     AS ferramenta,
    CAST(t.UID AS STRING)                           AS id_na_ferramenta,
    t.fase,
    t.Name                                          AS tarefa,
    CAST(NULL AS STRING)                            AS responsavel,   -- o XML não traz o recurso na tarefa
    to_date(t.Baseline.Start)                       AS inicio_baseline,
    to_date(t.Baseline.Finish)                      AS fim_baseline,
    to_date(t.ActualStart)                          AS inicio_real,
    to_date(t.ActualFinish)                         AS fim_real,
    CAST(t.PercentComplete AS DOUBLE)               AS pct_como_veio,
    -- #12: 'PT40H0M0S' → 40
    CAST(regexp_extract(t.Work, 'PT([0-9]+)H', 1) AS DOUBLE) AS horas
  FROM com_fase t
  LEFT JOIN projetos p
    ON p.ferramenta = 'msproject'
   AND p.codigo_ferramenta = t.arquivo
  -- #10: só as tarefas de verdade (as resumo somam as de baixo e contariam em dobro)
  WHERE t.Summary = 0
)
SELECT
  projeto_id, ferramenta, id_na_ferramenta, fase, tarefa, responsavel,
  inicio_baseline, fim_baseline, inicio_real, fim_real, pct_como_veio, horas,
  CASE WHEN pct_como_veio >= 100 THEN 'concluida'
       WHEN pct_como_veio  = 0   THEN 'a_fazer'
       ELSE 'em_andamento' END                      AS status_na_ferramenta
FROM limpo;


-- ---------------------------------------------------------------------------------------------
-- 4) A materialized view: as três empilhadas, num modelo só
-- ---------------------------------------------------------------------------------------------
CREATE OR REFRESH MATERIALIZED VIEW tarefas (
  CONSTRAINT achou_o_projeto  EXPECT (projeto_id IS NOT NULL)            ON VIOLATION FAIL UPDATE,
  CONSTRAINT pct_entre_0_e_100 EXPECT (pct_concluido BETWEEN 0 AND 100)  ON VIOLATION FAIL UPDATE,
  CONSTRAINT horas_positivas  EXPECT (horas > 0)                         ON VIOLATION FAIL UPDATE
)
COMMENT 'Todas as tarefas dos cronogramas dos 60 projetos, integrando as três ferramentas (Excel, ClickUp e MS Project) num modelo só: projeto, fase, responsável, datas baseline e reais, % concluído, horas previstas e status. Guarda a fotografia de hoje (as ferramentas não têm histórico).'
AS
WITH empilhado AS (
  SELECT * FROM tarefas_excel
  UNION ALL
  SELECT * FROM tarefas_clickup
  UNION ALL
  SELECT * FROM tarefas_msproject
)
SELECT
  concat_ws('-', projeto_id, ferramenta, id_na_ferramenta) AS tarefa_id,
  projeto_id,
  ferramenta,
  id_na_ferramenta,
  fase,
  tarefa,
  responsavel,
  inicio_baseline,
  fim_baseline,
  inicio_real,
  fim_real,
  -- #5: 11 tarefas do Excel vieram acima de 100%: limitamos a 100 e deixamos a flag
  least(pct_como_veio, 100)                         AS pct_concluido,
  pct_como_veio > 100                               AS pct_veio_acima_de_100,
  pct_como_veio,
  horas,
  status_na_ferramenta
FROM empilhado;
