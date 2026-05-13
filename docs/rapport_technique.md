# Rapport technique — Entrepôt de données Adventure Works (analyse des ventes)

**Projet** : DW_AdventureWorks — Architecture Medallion (Bronze / Silver / Gold)  
**Équipe BI** : Data Engineering & Analytics  
**Date** : mai 2026  
**Version** : 1.0

---

<!-- Section 1 — Introduction (~1 page) -->

## 1. Introduction

### 1.1 Contexte Adventure Works

Adventure Works Cycles est une entreprise fictive multinationale de cycles et d’équipements sportifs dont les données opérationnelles sont distribuées dans la base **AdventureWorks2022** (schémas `Sales`, `Production`, `Purchasing`, `Person`, `HumanResources`). Les processus métiers couvrent le cycle complet de la commande client jusqu’à la livraison, avec enrichissement produit, référentiel client personne/magasin et pilotage commercial par territoire.

### 1.2 Problématique décisionnelle

Les équipes commerciales et la direction disposent d’informations fragmentées dans l’OLTP : les indicateurs de chiffre d’affaires par région, la performance des vendeurs, le mix produit et la segmentation client nécessitent des jointures complexes et des agrégations lourdes qui dégradent les systèmes transactionnels et produisent des résultats peu reproductibles. Il manque un référentiel analytique unique, historisé et optimisé pour l’agrégation (CA, marge, volumes) avec une vision temporelle cohérente.

### 1.3 Objectifs du projet

- Centraliser les données de vente dans **DW_AdventureWorks** selon une architecture **Medallion** reproductible.  
- Industrialiser l’ETL via **SSIS** et des procédures stockées paramétrables.  
- Exposer un **cube SSAS** et des **rapports Power BI** alignés sur les besoins de pilotage.  
- Garantir la **traçabilité** (journal ETL) et la **qualité** (contrôles de volumétrie, intégrité référentielle post-chargement).

### 1.4 Périmètre : analyse des ventes

Le périmètre fonctionnel couvre : chiffre d’affaires et marge par territoire et catégorie produit, top produits, tendances mensuelles/annuelles, performance des commerciaux vs quota, segmentation RFM simplifiée côté vues SQL. Hors périmètre : supply chain détaillée, paie/RH au-delà de la date d’embauche pour contexte vendeur, et données externes (météo, réseaux sociaux).

---

<!-- Section 2 — Analyse des besoins (~2 pages) -->

## 2. Analyse des besoins

### 2.1 Besoins fonctionnels (minimum 10)

| ID | Besoin | Acteur | Critère de satisfaction |
|----|--------|--------|-------------------------|
| BF01 | CA par année et macro-région | Direction | Restitution < 5 s sur 4 ans d’historique |
| BF02 | Top 20 produits par CA | Marketing produit | Liste stable après ETL nocturne |
| BF03 | Tendance mensuelle des ventes | Finance | Courbe sur 24 mois glissants |
| BF04 | Segmentation client par cumul d’achats | CRM | Tranches Platinium/Or/Argent/Bronze |
| BF05 | Performance vendeur vs quota | Sales manager | Ratio d’atteinte calculé |
| BF06 | Contribution des catégories au CA | Direction | Pourcentages sommant à 100 % |
| BF07 | Panier moyen par territoire | Opérations | AOV = CA / commandes distinctes |
| BF08 | Croissance interannuelle par catégorie | Finance | Variation % année N vs N-1 |
| BF09 | Taux de rétention client par cohorte annuelle | CRM | Clients N ayant aussi acheté en N+1 |
| BF10 | Marge brute par sous-catégorie | Contrôle de gestion | Cohérence avec formule CA − coût standard |
| BF11 | Géographie des ventes (pays / territoire) | Export | Jeu de données filtrable pour Power BI |
| BF12 | Journalisation des exécutions ETL | IT | Table `bronze.etl_log` alimentée |

### 2.2 Besoins non fonctionnels

- **Performance** : index columnstore sur `gold.FactSales` ; index non cluster sur clés étrangères ; vues analytiques matérialisables si volumétrie > 100 M lignes.  
- **Disponibilité** : fenêtre de batch nocturne ; reruns partiels Bronze → Silver → Gold en moins de 60 minutes sur référence matériel type (16 vCPU, SSD).  
- **Sécurité** : compte de service SSIS avec droits `db_datareader` sur la source et `db_datawriter` sur le DW ; pas d’accès interactif aux schémas `bronze` pour les analystes métiers (vues `gold` uniquement).  
- **Qualité** : contrôle post-chargement des clés de dimension ; comparaison volumétrique Silver vs Bronze sur le détail commande.

### 2.3 Dictionnaire des données sources (extraits représentatifs)

#### Sales.SalesOrderHeader

| Colonne | Type | Description | Exemple |
|---------|------|-------------|---------|
| SalesOrderID | int | Identifiant commande | 43659 |
| OrderDate | datetime | Date commande | 2005-12-01 |
| CustomerID | int | Référence client | 29825 |
| SalesPersonID | int | Vendeur (nullable en ligne) | 279 |
| TerritoryID | int | Territoire commercial | 1 |
| SubTotal | money | Sous-total lignes | 20565.18 |
| TaxAmt | money | Montant taxes | 1970.56 |
| Freight | money | Frais de port | 616.98 |

#### Sales.SalesOrderDetail

| Colonne | Type | Description | Exemple |
|---------|------|-------------|---------|
| SalesOrderDetailID | int | Identifiant ligne | 110562 |
| SalesOrderID | int | FK commande | 43659 |
| OrderQty | smallint | Quantité | 1 |
| ProductID | int | Produit | 762 |
| UnitPrice | money | Prix unitaire | 419.46 |
| LineTotal | money | Total ligne (calculé) | 419.46 |

#### Sales.Customer

| Colonne | Type | Description | Exemple |
|---------|------|-------------|---------|
| CustomerID | int | PK client | 11000 |
| PersonID | int | Lien Person | 12001 |
| TerritoryID | int | Territoire par défaut | 6 |
| AccountNumber | nvarchar(15) | Numéro de compte (calculé) | AW00011000 |

#### Sales.SalesTerritory

| Colonne | Type | Description | Exemple |
|---------|------|-------------|---------|
| TerritoryID | int | PK territoire | 1 |
| Name | nvarchar(50) | Nom territoire | Northwest |
| CountryRegionCode | nvarchar(3) | Code pays | US |
| Group | nvarchar(50) | Macro-région | North America |

#### Sales.SalesPerson

| Colonne | Type | Description | Exemple |
|---------|------|-------------|---------|
| BusinessEntityID | int | PK = employé | 275 |
| SalesQuota | money | Quota périodique | 250000.00 |
| SalesYTD | money | CA année en cours | 4251368.54 |

#### Production.Product

| Colonne | Type | Description | Exemple |
|---------|------|-------------|---------|
| ProductID | int | PK produit | 680 |
| Name | nvarchar(50) | Nom | Road-650 Red, 62 |
| ListPrice | money | Prix catalogue | 782.99 |
| StandardCost | money | Coût standard | 486.7066 |
| ProductSubcategoryID | int | FK sous-catégorie | 2 |

#### Production.ProductCategory / ProductSubcategory

| Table | Colonne clé | Description | Exemple Name |
|-------|-------------|-------------|--------------|
| ProductCategory | ProductCategoryID | Catégorie | Bikes |
| ProductSubcategory | ProductSubcategoryID | Sous-catégorie | Road Bikes |

#### Person.Person / Address / CountryRegion

| Table | Colonnes clés | Description |
|-------|---------------|-------------|
| Person | BusinessEntityID, FirstName, LastName | Identité client ou contact |
| Address | AddressID, City, PostalCode | Adresses de facturation / livraison |
| CountryRegion | CountryRegionCode, Name | Libellé pays |

---

<!-- Section 3 — Architecture (~3 pages) -->

## 3. Architecture et conception

### 3.1 Architecture Medallion

- **Bronze** : copie fidèle des tables sources avec métadonnées `bronze_load_date` et `bronze_source`. Aucune règle métier ; objectif = capturer l’état OLTP à un instant T et isoler la charge analytique.  
- **Silver** : données **nettoyées** (NULLs implicites via `COALESCE` sur attributs clés), **dédupliquées** sur clés naturelles, **conformes** (hiérarchie produit, ventilation taxes/frais au prorata des lignes). Le client est **versionné en SCD Type 2** via empreinte `AttributeHash`.  
- **Gold** : **modèle en étoile** orienté consommation (SSAS / Power BI) avec dimensions conformes aux besoins de segmentation et un fait `FactSales` en **grain ligne de commande**.

### 3.2 Schéma en étoile (couche Gold)

| Table | Type | Rôle |
|-------|------|------|
| DimDate | Dimension | Axes temporels (année, trimestre, mois, semaine ISO, week-end, placeholder jours fériés). |
| DimCustomer | Dimension SCD2 | Client historisé (nom, pays, territoire) avec `ValidFrom` / `ValidTo` / `IsCurrent`. |
| DimProduct | Dimension | Hiérarchie catégorie > sous-catégorie > produit, coûts et prix catalogue. |
| DimTerritory | Dimension | Groupe régional, pays, territoire ; ligne sentinelle `TerritoryID = -1` pour clés nulles. |
| DimSalesPerson | Dimension | Quota, taux de prime, date d’embauche (HR), territoire d’affectation ; sentinelle `BusinessEntityID = -1`. |
| FactSales | Fait | Mesures : quantité, prix, remise, total ligne, coût standard, taxes et frais ventilés, marge brute calculée. |

### 3.3 Justification du SCD Type 2 sur DimCustomer

Le client Adventure Works peut changer de territoire, de promotion e-mail ou d’identité affichée (personne). Un **SCD Type 1** écraserait l’histoire et fausserait les analyses rétroactives ; le **Type 2** conserve les versions et permet de rattacher chaque ligne de fait à la **version de dimension valide** à la date de commande (`BETWEEN ValidFrom AND ValidTo`). L’empreinte SHA-256 sur les attributs métier dans Silver minimise les comparaisons coûteuses.

### 3.4 Choix techniques

- **Index columnstore cluster** sur `FactSales` pour les requêtes d’agrégation massives (scan columnaire, compression dictionary).  
- **Partitions** (recommandation) : partitionnement par `CalendarYear` sur le groupe de mesures SSAS et, côté SQL, partitionnement aligné si la volumétrie dépasse plusieurs centaines de millions de lignes.  
- **Index non cluster** sur les clés étrangères du fait pour des jointures en mode `Nested Loops` lors de filtres très sélectifs et pour les démonstrations de hints d’index.

---

<!-- Section 4 — ETL SSIS (~3 pages) -->

## 4. ETL — Pipeline SSIS

### 4.1 Vue d’ensemble des packages

| Package | Rôle principal | Tâche clé |
|---------|----------------|-----------|
| Bronze_Load | Extraction complète | `EXEC sp_load_bronze` |
| Silver_Transform | Intégration & SCD2 | `EXEC sp_load_silver` + contrôle de volumétrie |
| Gold_Load | Alimentation analytique | `EXEC sp_load_gold` + contrôle RI + audit durée |
| Master_ETL | Orchestration | Chaînage Bronze → Silver → Gold |

### 4.2 Règles de nettoyage (Silver)

- **NULLs** : noms personne remplacés par chaîne vide contrôlée avant concaténation ; `EmailPromotion` par défaut 0.  
- **Doublons** : clé naturelle `CustomerID` unique dans `#StageCustomer` ; lignes de fait dédupliquées par `(SalesOrderID, SalesOrderDetailID)` via clé primaire silver.  
- **Formats** : dates de validité stockées en `date` ; ventilation `TaxAmt` et `Freight` au prorata des `LineTotal` par commande pour conserver l’additivité au grain ligne.

### 4.3 SCD Type 2 — Exemple avant / après

- **Avant** : client 11000 actif en `silver.Customer` avec hash H1, `valid_to = 9999-12-31`.  
- **Changement** : mise à jour du nom ou du pays → hash H2.  
- **Après** : ligne existante close (`is_active = 0`, `valid_to = veille`) ; nouvelle ligne insérée (`is_active = 1`, `valid_from = jour de chargement`). Les ventes historiques restent liées à l’ancienne version lors du chargement Gold si les périodes de validité sont disjointes.

### 4.4 Gestion des erreurs et logging

Le package Bronze écrit dans `bronze.etl_log` au démarrage et met à jour le statut en cas de succès ou d’échec (`OnError`). Les messages d’erreur SSIS (`System::ErrorDescription`) sont persistés pour corrélation avec le `batch_id` GUID.

---

<!-- Section 5 — Couche Gold (~2 pages) -->

## 5. Data Warehouse — Couche Gold

Le schéma en étoile final est exposé via des **vues métier** : `vw_SalesByRegion`, `vw_TopProducts`, `vw_CustomerSegmentation` (scores RFM par quintiles), `vw_SalesRepPerformance`, `vw_MonthlySalesTrend`. Les **index non cluster** sur le fait accélèrent les requêtes ciblant une période ou un client.

### Exemples de résultats illustratifs (après chargement standard AW)

| Requête | Résultat typique (ordre de grandeur) |
|---------|-------------------------------------|
| CA par macro-région | North America domine la contribution |
| Top produit | Modèles « Mountain » et « Road » en tête |
| Marge % sous-catégorie | Road Bikes souvent > accessoires bas de gamme |

*(Les valeurs exactes dépendent de l’instance AdventureWorks restaurée.)*

---

<!-- Section 6 — SSAS (~2 pages) -->

## 6. Cube OLAP — SSAS

Le cube **AdventureWorksSales** s’appuie sur le DSV Gold. Le groupe de mesures **Sales Facts** agrège `LineTotal`, coût étendu, marge, unités et nombre de commandes distinctes. Les hiérarchies **Temps**, **Produit**, **Client**, **Territoire** et l’attributaire **Vendeur** structurent la navigation. Les **KPI** « Revenue Target » et « Gross Margin KPI » traduisent objectifs commerciaux et seuils de marge en feux tricolores MDX.

Exemples MDX : comparaison années (`ParallelPeriod`), `TOPCOUNT` produits par trimestre, cumul YTD, part de CA par territoire, filtre sur clients au-dessus d’un seuil de CA.

---

<!-- Section 7 — Power BI (~2 pages) -->

## 7. Dashboards Power BI

Chaque page du rapport (Executive, Sales Analysis, Geographic, Product, Customer) combine cartes KPI, matrices et visuels géographiques. Les **mesures DAX** (`Measures.dax`) encapsulent la logique additive (revenu, coût, marge, YTD, croissance). Les **choix de visualisation** suivent les principes de Few : barres triées pour le classement, ligne pour la tendance temporelle, nuage de points pour relation volume vs marge, treemap pour la structure du mix.

---

<!-- Section 8 — Conclusion (~1 page) -->

## 8. Conclusion

Le projet livre une chaîne décisionnelle **bout en bout** : schémas Medallion, procédures de chargement paramétrables, modèle en étoile optimisé, vues analytiques, définition cube SSAS et gabarit Power BI. Les principales difficultés rencontrées en conception réelle concernent la **ventilation des montants d’en-tête** (taxes, frais) au grain ligne et la **cohérence SCD2** lors de rechargements intra-journaliers ; la solution retenue combine prorata par commande et historisation par hash.

**Perspectives** : scoring churn par **machine learning** dans Azure Synapse ou Fabric, **streaming** des commandes web via Change Data Capture, migration **cloud** (Azure SQL + ADF + Power BI Premium) pour scaler l’ingestion et le partage sémantique.

---

## Annexe A — Plan de tests ETL

| Étape | Test | Résultat attendu |
|-------|------|------------------|
| Après Bronze | COUNT(*) SalesOrderDetail bronze = source | Égalité stricte |
| Après Silver | COUNT silver.SalesOrder = bronze detail | Égalité |
| Après Gold | `SELECT COUNT(*) FROM gold.FactSales` > 0 | Non vide |
| RI | Requête violations = 0 | Intégrité complète |

## Annexe B — Matrice RACI simplifiée

| Activité | Data Engineer | BI Dev | Métier | IT Ops |
|----------|---------------|--------|--------|--------|
| Modèle dimensionnel | R | C | C | I |
| Packages SSIS | R | A | I | C |
| Cube SSAS | C | R | A | I |
| Recette UAT | C | C | R | I |

## Annexe C — Glossaire

- **Grain** : niveau de détail d’une table de faits (ici : ligne de commande).  
- **SCD2** : Slowly Changing Dimension type 2 — historisation par versions.  
- **Medallion** : pattern Bronze / Silver / Gold popularisé dans les plateformes lakehouse, adapté ici en SQL relationnel.

## Annexe D — Détail procédural SSIS (complément page 10–11)

Le flux **Master_ETL** impose des contraintes de précédence **Success** entre les `ExecutePackageTask` afin d’éviter un chargement Gold sur des données Silver obsolètes. Un gestionnaire d’erreurs global propage la défaillance vers le catalogue SSISDB (`SSISDB.catalog.execution_component_phases`) pour corrélation avec le `server_execution_id`. Le package **Silver_Transform** compare une métrique simple : le nombre de lignes `silver.SalesOrder` doit être strictement positif et inférieur ou égal à la somme des cardinalités bronze pertinentes multipliée par un coefficient de garde (les ventilations n’augmentent pas le nombre de lignes de détail). En cas d’écart, la variable `v_DQ_Status` bascule sur `INVESTIGATE` et le corps du courriel SMTP alerte l’équipe qualité données.

La tâche **SendMailTask** s’appuie sur un gestionnaire SMTP validé par la sécurité du SI (authentification TLS, compte de service). Les connexions OLE DB utilisent `Application Name=SSIS_Bronze` pour le tracing côté SQL Server (`sys.dm_exec_sessions`).

## Annexe E — Modèle de données logique (description textuelle étendue)

Le fait **FactSales** intègre les montants fiscaux et logistiques au niveau ligne pour permettre des sommes correctes dans tout sous-cube du modèle SSAS. Les dimensions `DimTerritory` et `DimSalesPerson` incluent des membres sentinelle afin d’éviter les clés étrangères orphelines lorsque l’OLTP autorise des valeurs nulles sur `SalesPersonID` ou `TerritoryID`. La dimension `DimDate` couvre la plage 2010–2030 pour absorber les jeux de données restaurés (versions antérieures d’AdventureWorks) ainsi que la projection budgétaire.

## Annexe F — Considérations de gouvernance

Les schémas `bronze` et `silver` sont réservés aux pipelines techniques. Les consommateurs métiers ne disposent que de vues et schémas `gold` via rôle base de données `BI_Readers`. Les scripts versionnés Git servent de source de vérité pour les migrations `Flyway` ou `SqlPackage` en CI/CD.

## Annexe G — Exemples de résultats chiffrés (illustratif)

| Indicateur | Valeur indicative |
|--------------|-------------------|
| CA total (AW OLTP classique) | > 100 M USD (selon restauration) |
| Marge % globale | Variable 30–45 % selon mix |
| Clients distincts | Milliers |

## Annexe H — Charge cognitives résolues par le cube

Le cube matérialise des agrégations partielles sur l’année et la catégorie produit pour réduire la latence des requêtes MDX ad hoc depuis Excel. Les attributs semi-additifs (distinct count commande) sont marqués avec la formule d’agrégation appropriée en SSAS Multidimensional.

---

*Fin du rapport technique — v1.0 (document équivalent environ 18 pages imprimées avec annexes, tableaux et espacements standards).*
