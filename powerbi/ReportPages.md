# Pages de rapport Power BI — Adventure Works Sales

Ce document décrit la disposition visuelle et l’intention analytique de chaque page du fichier `AdventureWorks_Sales.pbix` (connexion au modèle importé depuis `DW_AdventureWorks.gold` ou dataset publié).

## Page 1 — Executive Dashboard

- **Cartes KPI** (haut de page, alignement horizontal) : `Total Revenue`, `Gross Margin %`, `Order Count`, `Customer Count`. Format monétaire pour le chiffre d’affaires, pourcentage à une décimale pour la marge.
- **Graphique en courbes** : axe X = `DimDate[FullDate]` agrégé au mois ; deux séries : `YTD Revenue` et `PYTD Revenue` pour comparer la trajectoire cumulée à l’année glissante.
- **Histogramme (barres)** : axe X = `DimTerritory[RegionGroup]` ; valeurs = `Total Revenue`. Tri décroissant pour mettre en avant les macro-régions commerciales.
- **Anneau (donut)** : légende = `DimProduct[CategoryName]` ; valeurs = `Total Revenue`. Légende positionnée à droite pour préserver la lisibilité du trou central (espace pour un libellé de filtre global).

## Page 2 — Sales Analysis

- **Matrice** : hiérarchie lignes `DimTerritory[TerritoryName]` > `DimTerritory[CountryName]` > `DimSalesPerson[BusinessEntityID]` (afficher nom via colonne calculée `SalesPersonName` si disponible) ; colonnes = `Total Revenue`, `Gross Margin %`, `Order Count`. Activer les totaux partiels et le style en bandes pour la lecture rapide.
- **Nuage de points** : axe X = `Units Sold` ; axe Y = `Gross Margin %` ; taille des bulles = `Total Revenue` ; détail = `DimProduct[ProductName]`. Filtre croisé depuis la matrice pour analyser un vendeur.
- **Cascade (waterfall)** : catégorie = `DimProduct[CategoryName]` ; valeur YTD = `YTD Revenue` pour visualiser la contribution marginale de chaque catégorie au cumul annuel.

## Page 3 — Geographic Analysis

- **Carte remplie ou bulles** : emplacement = `DimTerritory[CountryName]` ; taille = `Total Revenue`. Utiliser le thème clair et une échelle de couleurs séquentielle bleue.
- **Barres horizontales** : Top 10 des `DimTerritory[TerritoryName]` par `Total Revenue`, tri décroissant, étiquettes de données activées.
- **Tableau** : colonnes pays / territoire avec `Total Revenue`, `Avg Order Value`, `Gross Margin %`, `Customer Count`. Mise en forme conditionnelle sur la marge pour signaler les pays sous-performants.

## Page 4 — Product Performance

- **Barres verticales** : Top 20 `DimProduct[ProductName]` par `Total Revenue`.
- **Tableau matriciel** : hiérarchie `CategoryName` > `SubcategoryName` > `ProductName` avec `Total Revenue`, `Units Sold`, `Gross Margin`, `Gross Margin %`.
- **Treemap** : groupe = `CategoryName` et `SubcategoryName` ; valeurs = `Total Revenue` pour visualiser la densité du mix produit.

## Page 5 — Customer Analysis

- **Histogramme** : axe = tranches de `Revenue per Customer` (bins créés dans Power Query ou colonne calculée par tranche de 500) ; fréquence = nombre de clients.
- **Courbes doubles** : mois sur l’axe X ; mesures `New Customers` (définie comme première apparition du `CustomerID` dans FactSales) et `Returning Customers` (clients avec au moins deux mois distincts d’achat) — implémentées via colonnes calculées ou tables de dates d’entrée.
- **Tableau** : Top 20 clients par `Total Revenue` avec colonnes `CustomerName`, `CountryName`, `Total Revenue`, `Order Count`, `Gross Margin %`.

### Paramètres recommandés

- **Segment de dates** : lié à `DimDate[FullDate]`.
- **Filtres de page** : `DimProduct[CategoryName]`, `DimTerritory[RegionGroup]`.
- **Thème** : couleurs alignées sur la charte Adventure Works (bleu #1F4E79, gris #7F7F7F, accent orange #C55A11).
