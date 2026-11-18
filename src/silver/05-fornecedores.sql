-- silver.entregas_fornecedor
-- Sujeira tratada aqui: #15 a mesma consultoria escrita de 4 jeitos.
-- data_entrega vazia NÃO é sujeira: é entrega em aberto.

CREATE OR REFRESH MATERIALIZED VIEW entregas_fornecedor
COMMENT 'Entregas das consultorias contratadas: o que foi pedido, quando foi prometido e quando chegou. Traz os prazos (prometido e real, em dias), os dias de atraso na entrega e as flags em_aberto e em_atraso (em aberto e com a data prometida antes de hoje, 16/10/2026).'
AS
WITH limpo AS (
  SELECT
    entrega_id,
    projeto_id,
    -- #15: 'CodeForge Consultoria Ltda', 'Codeforge Consultoria', 'CODEFORGE CONSULTORIA LTDA',
    -- 'Code Forge Consultoria' → um nome só
    CASE WHEN replace(lower(fornecedor), ' ', '') LIKE '%codeforge%'
         THEN 'CodeForge Consultoria Ltda'
         ELSE fornecedor END                        AS fornecedor,
    fornecedor                                      AS fornecedor_como_veio,
    item,
    CAST(replace(valor, ',', '.') AS DECIMAL(18, 2)) AS valor,
    to_date(data_pedido)                            AS data_pedido,
    to_date(data_prometida)                         AS data_prometida,
    try_to_date(nullif(trim(data_entrega), ''), 'yyyy-MM-dd') AS data_entrega,
    CAST(prazo_contratado_dias AS INT)              AS prazo_contratado_dias,
    status
  FROM lakehouse_vertice.bronze.entregas_fornecedor
)
SELECT
  entrega_id,
  projeto_id,
  fornecedor,
  fornecedor_como_veio,
  item,
  valor,
  data_pedido,
  data_prometida,
  data_entrega,
  prazo_contratado_dias,
  status,
  datediff(data_prometida, data_pedido)             AS prazo_prometido_dias,
  datediff(data_entrega,   data_pedido)             AS prazo_real_dias,       -- NULL se em aberto
  datediff(data_entrega,   data_prometida)          AS dias_de_atraso_na_entrega, -- negativo = chegou antes
  data_entrega IS NULL                              AS em_aberto,
  (data_entrega IS NULL AND data_prometida < DATE'2026-10-16') AS em_atraso
FROM limpo;
