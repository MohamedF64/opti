/// Modèle de configuration : copie ce fichier en lib/config.dart (jamais publié) et remplis-le.
///
/// La clé publiable Supabase (Project Settings › API Keys) est conçue pour être publique : sans ton
/// mot de passe et ton code à 6 chiffres, elle ne donne accès à rien (RLS + inscriptions fermées).
/// Ne mets jamais de clé secrète dans l'app.
library;

const supabaseUrl = 'https://<ton-projet>.supabase.co';
const supabasePublishableKey = 'sb_publishable_…';
const backendUrl = 'https://<ton-projet>.vercel.app';
const emailParDefaut = ''; // prérempli sur l'écran de connexion (facultatif)
const prenom = ''; // « Bonjour, … » sur l'accueil
