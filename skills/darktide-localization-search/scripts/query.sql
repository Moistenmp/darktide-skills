WITH matched AS MATERIALIZED (
    SELECT * FROM localization WHERE /*FILTERS*/
), page AS (
    SELECT * FROM matched ORDER BY resource, hash LIMIT @take OFFSET @offset
)
SELECT json_object(
    'total', (SELECT count(*) FROM matched),
    'offset', @offset,
    'limit', @limit,
    'matches', json((SELECT json_group_array(json_object(
        'resource', resource,
        'hash', hash,
        'keys', json((SELECT json_group_array(key) FROM (
            SELECT key FROM key_names WHERE hash = page.hash ORDER BY key
        ))),
        'comment', comment,
        'translations', json_object(/*TRANSLATIONS*/)
    )) FROM page))
);
