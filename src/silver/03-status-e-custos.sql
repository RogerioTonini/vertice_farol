-- silver.status_semanal e silver.custos
-- Sujeiras tratadas aqui: #13 vírgula decimal, #14 estorno negativo, #17 farol em caixas
-- diferentes, #18 status vazio.


-- O status que o gerente manda toda sexta. É a ÚNICA fonte do histórico de avanço.
CREATE OR REFRESH MATERIALIZED VIEW status_semanal (
  CONSTRAINT farol_conhecido EXPECT (farol IN ('verde', 'amarelo', 'vermelho')) ON VIOLATION FAIL UPDATE
)
COMMENT 'Status semanal (toda sexta) de cada projeto enviado pelo gerente: % concluído, farol do gerente (verde, amarelo, vermelho) e o texto livre com entregas e bloqueios. status_vazio marca os textos sem conteúdo (vazio, N/A, ver ata da reunião), que são mantidos.'
AS
SELECT
  projeto_id,
  coalesce(try_to_date(data_status, 'yyyy-MM-dd'),
           try_to_date(data_status, 'dd/MM/yyyy'))  AS data_status,
  gerente,
  -- #17: 'Verde', 'VERDE', ' verde ' → 'verde'
  lower(trim(farol))                                AS farol,
  CAST(CAST(trim(pct_concluido) AS DOUBLE) AS INT)  AS pct_concluido,
  texto_status,
  -- #18: NÃO descartamos a linha: o farol e o % continuam valendo. Só sinalizamos.
  (texto_status IS NULL
   OR trim(texto_status) IN ('', 'N/A', 'ver ata da reunião'))  AS status_vazio
FROM lakehouse_vertice.bronze.status_semanal;


-- Os lançamentos de custo real.
CREATE OR REFRESH MATERIALIZED VIEW custos
COMMENT 'Lançamentos de custo real por projeto (pessoal, consultoria, cloud, licenças, despesas), em reais. Estornos ficam como valor negativo (o custo é líquido) e são sinalizados em estorno. semana é a sexta-feira da semana do lançamento.'
AS
SELECT
  lancamento_id,
  projeto_id,
  to_date(data)                                     AS data,
  -- semana = a sexta da semana (date_trunc('WEEK') dá a segunda: + 4 dias)
  date_add(to_date(date_trunc('WEEK', to_date(data))), 4) AS semana,
  categoria,
  descricao,
  -- #13: 671 valores com vírgula decimal ('12345,67'). replace ANTES do CAST.
  -- Nunca try_cast: ele viraria NULL e jogaria R$ 5,4 mi fora em silêncio.
  CAST(replace(valor, ',', '.') AS DECIMAL(18, 2))  AS valor,
  -- #14: estorno FICA (custo líquido), só sinalizado
  CAST(replace(valor, ',', '.') AS DECIMAL(18, 2)) < 0 AS estorno,
  centro_custo
FROM lakehouse_vertice.bronze.custos;
