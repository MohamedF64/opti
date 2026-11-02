-- Synchros automatiques : le cron appelle le backend chaque heure de 6 h à 20 h (UTC) ;
-- le backend ne synchronise qu'à 8, 12, 17 et 21 h, heure de Paris (4 par jour = maximum DSP2).
-- Avant : extensions pg_cron et pg_net activées, CRON_SECRET rangé dans le Vault sous le nom « cron_secret ».
-- Remplace <ton-backend> par le domaine de production Vercel.

select cron.schedule(
  'opti-synchro',
  '0 6-20 * * *',
  $$
  select net.http_get(
    url := 'https://<ton-backend>.vercel.app/banque/synchro/cron',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (select decrypted_secret from vault.decrypted_secrets where name = 'cron_secret')
    ),
    timeout_milliseconds := 60000
  );
  $$
);
