# DW_AdventureWorks — Entrepôt de données Adventure Works (ventes)

![SQL Server](https://img.shields.io/badge/SQL%20Server-2022-red?style=flat-square&logo=microsoftsqlserver)
![SSIS](https://img.shields.io/badge/SSIS-Integration%20Services-512BD4?style=flat-square&logo=microsoft)
![SSAS](https://img.shields.io/badge/SSAS-Analysis%20Services-512BD4?style=flat-square&logo=microsoft)
![Power BI](https://img.shields.io/badge/Power%20BI-Desktop-F2C811?style=flat-square&logo=powerbi)

## Description du projet

Ce dépôt contient un **entrepôt de données décisionnel** centré sur l’**analyse des ventes** pour la base **AdventureWorks2022**. L’architecture suit le modèle **Medallion** (schémas `bronze`, `silver`, `gold`) sur une base SQL Server dédiée **`DW_AdventureWorks`**, avec procédures stockées d’alimentation, vues analytiques, documentation **SSIS**, définition **SSAS** et mesures **Power BI**.

## Architecture (vue logique)

```
┌─────────────────────────┐
│   AdventureWorks2022    │  OLTP (Sales, Production, Person, …)
│        (source)         │
└───────────┬─────────────┘
            │  sp_load_bronze
            ▼
┌─────────────────────────┐
│  DW_AdventureWorks       │
│  ┌───────────────────┐  │
│  │ bronze  (RAW)     │  │
│  └─────────┬─────────┘  │
│            │ sp_load_silver
│  ┌─────────▼─────────┐  │
│  │ silver (clean)    │  │
│  └─────────┬─────────┘  │
│            │ sp_load_gold
│  ┌─────────▼─────────┐  │
│  │ gold (star)       │──┼──► SSAS Cube / Power BI
│  └───────────────────┘  │
└─────────────────────────┘
```

## Prérequis (versions indicatives)

| Composant | Version |
|-----------|---------|
| Microsoft SQL Server | 2022 (ou 2019 minimum pour certaines fonctionnalités columnstore) |
| Base OLTP | AdventureWorks2022 restaurée sur la même instance |
| Visual Studio + SSDT | 2022 (projets SSIS **ProjectDeployment** ou **PackageDeployment**) |
| SQL Server Data Tools — BI | Pour SSAS Multidimensional |
| Power BI Desktop | 2.130.x (canal mensuel) ou version entreprise équivalente |

## Installation (ordre d’exécution des scripts SQL)

1. Ouvrir **SQL Server Management Studio** (SSMS) et se connecter à l’instance hébergeant `AdventureWorks2022`.
2. Exécuter dans l’ordre :
   - `sql-scripts/00_create_database.sql`
   - `sql-scripts/01_bronze_tables.sql`
   - `sql-scripts/02_silver_tables.sql`
   - `sql-scripts/03_gold_tables.sql`
   - `ssis-packages/create_bronze_etl_log.sql` (journal ETL)
   - `sql-scripts/04_stored_procedures.sql`
   - `sql-scripts/05_indexes_and_views.sql`
3. Charger les données :
   ```sql
   USE DW_AdventureWorks;
   EXEC dbo.sp_populate_dim_date @StartYear = 2010, @EndYear = 2030;
   EXEC dbo.sp_load_bronze @SourceDatabase = N'AdventureWorks2022';
   EXEC dbo.sp_load_silver;
   EXEC dbo.sp_load_gold @SourceDatabase = N'AdventureWorks2022';
   ```
4. Exécuter les requêtes d’exemple : `sql-scripts/06_analytical_queries.sql`

## Structure des dossiers

```
Dataware/
├── sql-scripts/          # DDL, procédures, index, vues, requêtes analytiques
├── ssis-packages/      # Pseudocode XML + script create_bronze_etl_log.sql
├── ssas-cube/          # Définition textuelle du cube AdventureWorksSales
├── powerbi/            # Mesures DAX + description des pages de rapport
└── docs/               # Rapport technique (français)
```

## Exécution du pipeline ETL (SSIS)

1. Créer un projet **Integration Services** dans Visual Studio.
2. Implémenter les packages en suivant les fichiers `*.pseudocode.xml` du dossier `ssis-packages/` (`Bronze_Load`, `Silver_Transform`, `Gold_Load`, `Master_ETL`).
3. Déployer le projet sur **SSISDB** et planifier un **SQL Server Agent Job** qui exécute `Master_ETL.dtsx` après la sauvegarde OLTP.

## Déploiement du cube SSAS

1. Créer un projet **Analysis Services Multidimensional** (ou Tabular si adaptation DAX).
2. Définir la source de données vers `DW_AdventureWorks` et importer le schéma `gold` selon `ssas-cube/AdventureWorksSales_cube_definition.txt`.
3. Déployer sur l’instance SSAS et traiter les dimensions puis le groupe de mesures `Sales Facts`.

## Ouverture Power BI

1. Lancer **Power BI Desktop**.
2. **Obtenir des données** → **SQL Server** → serveur + base `DW_AdventureWorks`.
3. Sélectionner les tables `gold` nécessaires (ou une vue consolidée) et importer.
4. Copier les mesures depuis `powerbi/Measures.dax` dans des **mesures de table** (table `_Measures` dédiée recommandée).
5. Disposer les visuels selon `powerbi/ReportPages.md`.

## Membres de l’équipe

| Rôle | Nom |
|------|-----|
| Chef de projet BI | Étudiant 1 |
| Ingénieur données | Étudiant 2 |
| Développeur SSIS / SQL | Étudiant 3 |
| Analyste Power BI | Étudiant 4 |

## Licence

Projet pédagogique basé sur les données **Adventure Works** fournies par Microsoft (licence des exemples SQL Server).
