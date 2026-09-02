# Factur-X Generator pour Ruby

Un script Ruby complet pour **générer un XML Factur-X conforme EN 16931** et **l'intégrer dans un PDF existant** (comme ceux générés par Facturation.pro), afin de créer un fichier compatible avec **SuperPDP** et les autres Plateformes de Dématérialisation Partenaire (PDP).

## 📋 À propos

**Factur-X** est un format hybride de facture électronique qui combine :
- Un **PDF lisible par l'humain** (PDF/A-3)
- Un **fichier XML structuré** conforme à la norme européenne EN 16931 (syntaxe CII D22B)

Ce format est **obligatoire en France à partir de 2026** pour la facturation électronique entre entreprises.

## ✅ Fonctionnalités

- ✅ Génération automatique d'un **XML Factur-X conforme** (CII D22B)
- ✅ Intégration du XML dans un **PDF existant** (même non PDF/A-3)
- ✅ Support des **5 profils Factur-X** : MINIMUM, BASIC, BASICWL, EN16931, EXTENDED
- ✅ Configuration **personnalisable** (fournisseur, client, lignes de facture)
- ✅ **Mode interactif** pour saisir les informations
- ✅ **Validation** des données de base
- ✅ Compatible avec **SuperPDP** et les autres PDP

## 🚀 Installation

### 1. Prérequis

- **Ruby** 2.7 ou supérieur
- **Bundler** (pour gérer les dépendances)
- **Ghostscript** (nécessaire pour zugpferd)
- **qpdf** (méthode alternative si zugpferd échoue)

#### Installation des prérequis

**Sur Debian/Ubuntu :**
```bash
sudo apt-get update
sudo apt-get install ruby ruby-dev bundler ghostscript qpdf
```

**Sur macOS (avec Homebrew) :**
```bash
brew install ruby bundler ghostscript qpdf
```

### 2. Installation des gems

```bash
cd facturx
bundle install
```

## 🧪 Exécuter les tests

Pour vérifier que tout fonctionne correctement :

```bash
# Installer les dépendances (incluant rspec)
bundle install

# Exécuter tous les tests
bundle exec rspec

# Exécuter avec plus de détails
bundle exec rspec --format documentation

# Exécuter un fichier de test spécifique
bundle exec rspec spec/facturx_generator_spec.rb
```

**Résultats attendus** :
- 30+ tests passés ✅
- Tests de configuration, génération XML, et intégration PDF

## 📥 Utilisation

### Mode simple (avec configuration par défaut)

```bash
# Générer une facture Factur-X à partir d'un PDF
ruby facturx_generator.rb ma_facture.pdf

# Résultat : ma_facture_facturx.pdf (avec XML intégré)
```

### Mode avec configuration personnalisée

```bash
# Utiliser un fichier de configuration YAML
ruby facturx_generator.rb ma_facture.pdf --config ma_config.yaml

# Spécifier le profil Factur-X
ruby facturx_generator.rb ma_facture.pdf --profil EN16931

# Spécifier le fichier de sortie
ruby facturx_generator.rb ma_facture.pdf --output ma_facture_final.pdf
```

### Mode interactif

```bash
# Mode interactif pour saisir toutes les informations
ruby facturx_generator.rb ma_facture.pdf --interactive
```

### Mode ultra-simple

```bash
ruby facturx_simple.rb ma_facture.pdf "Nom du Client" 1200.00 FACT-001
```

## 📝 Configuration

### Fichier de configuration (config.yaml)

```yaml
# Profil Factur-X à utiliser
profil: "EN16931"

# Informations du fournisseur
fournisseur:
  nom: "MA SOCIETE"
  siren: "123456789"
  siret: "12345678900010"
  adresse: "123 Rue de la Facture"
  code_postal: "75001"
  ville: "PARIS"
  pays: "FR"
  telephone: "+33123456789"
  email: "contact@masociete.fr"
  iban: "FR7612345678901234567890123"
  bic: "BNPAFRPP"
  tva_intracommunautaire: "FR123456789"

# Informations du client
client:
  nom: "CLIENT TEST"
  siren: "987654321"
  adresse: "321 Rue du Client"
  code_postal: "75002"
  ville: "PARIS"
  pays: "FR"

# Paramètres de la facture
facture:
  numero: "FACT-2024-001"
  date: "2024-01-15"
  date_echeance: "2024-02-15"
  devise: "EUR"
  conditions_reglement: "30 jours net"

# Lignes de facture
lignes:
  - description: "Service de consultation"
    quantite: 1
    prix_unitaire: 100.00
    tva: 20.0
    unite: "UN"
  - description: "Frais de dossier"
    quantite: 1
    prix_unitaire: 50.00
    tva: 20.0
    unite: "UN"
```

## 🎯 Exemple complet

### 1. Personnaliser la configuration

Éditez le fichier `config.yaml` avec vos informations.

### 2. Générer la facture Factur-X

```bash
ruby facturx_generator.rb facture_fournisseur.pdf --config config.yaml
```

### 3. Vérifier le résultat

Ouvrez le fichier `facture_fournisseur_facturx.pdf` avec **Adobe Acrobat Reader** :
- Allez dans **Affichage → Afficher/masquer → Barre d'outils de pièce jointe**
- Vérifiez que `factur-x.xml` est présent

### 4. Valider avec un outil en ligne

Utilisez le [validateur Factur-X gratuit](https://e-invoice.be/blog/factur-x-format) pour vérifier la conformité.

## 🔧 Problèmes courants

### Erreur : "zugpferd nécessite Ghostscript"

Installez Ghostscript :
```bash
# Debian/Ubuntu
sudo apt-get install ghostscript

# macOS
brew install ghostscript
```

### Erreur : "qpdf n'est pas installé"

Installez qpdf :
```bash
# Debian/Ubuntu
sudo apt-get install qpdf

# macOS
brew install qpdf
```

### Erreur : "Bundler n'est pas installé"

Installez Bundler :
```bash
gem install bundler
```

### Le PDF généré n'est pas conforme PDF/A-3

Le script utilise zugpferd qui convertit automatiquement le PDF en PDF/A-3. Si vous rencontrez des problèmes, essayez :
1. De partir d'un PDF simple (sans images complexes)
2. D'utiliser la méthode alternative avec qpdf (déjà implémentée dans le script)

## 📚 Ressources

- [Site officiel Factur-X (FNFE-MPE)](https://fnfe-mpe.org/factur-x/)
- [Documentation EN 16931](https://ec.europa.eu/digital-building-blocks/wikis/display/DIGIT/EN+16931)
- [Validateur Factur-X en ligne](https://e-invoice.be/blog/factur-x-format)
- [SuperPDP - Plateforme de dématérialisation](https://www.superpdp.tech/)

## 🔄 Workflow avec Facturation.pro

1. **Exportez votre facture** depuis Facturation.pro en PDF
2. **Exécutez le script** : `ruby facturx_generator.rb facture_exportée.pdf --interactive`
3. **Saisissez les informations** demandées (numéro de facture, client, lignes, etc.)
4. **Récupérez le fichier** `facture_exportée_facturx.pdf`
5. **Envoyez via SuperPDP** comme une facture électronique standard

## 💡 Conseils

- **Testez toujours** vos fichiers Factur-X avec un validateur avant envoi
- **Conservez une copie** du PDF original et du XML généré
- **Personnalisez le profil** selon vos besoins (EN16931 est le plus courant)
- **Vérifiez les totaux** : le XML doit correspondre exactement au PDF

## 📜 Licence

MIT License - Libre d'utilisation pour un usage personnel ou professionnel.

---

**Auteur** : Script généré pour faciliter la transition vers la facturation électronique obligatoire en France.

**Contribuez** : Ce script est open source. N'hésitez pas à l'améliorer et à le partager !

**Besoin d'aide ?** Ouvrez une issue sur le dépôt GitHub ! 🎯
