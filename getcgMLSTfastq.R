library(httr)
library(jsonlite)
library(dplyr)
library(readr)
library(purrr)
library(stringr)
library(lubridate)
library(taxize)
library(tidyr)
library(readxl)

taxa <- readLines("cgMLST.txt")

get_taxid_safe <- function(taxon) {
  tryCatch({
    uid <- taxize::get_uid(taxon, ask = FALSE)[[1]]
    if (is.na(uid)) return(NA_integer_)

    uid <- gsub("txid", "", uid)
    as.integer(uid)
  }, error = function(e) {
    NA_integer_
  })
}


taxa_df <- tibble(
  taxon = taxa,
  taxid = map_int(taxon_names, ~
                    get_taxid_safe(.x)[[1]])
) |>
  filter(!is.na(taxid))

query_ena_isolate_runs <- function(taxid, limit = 500) {

  base_url <- "https://www.ebi.ac.uk/ena/portal/api/search"

  query <- paste0(
    "tax_eq(", taxid, ")",
    " AND library_layout=PAIRED",
    " AND instrument_platform=ILLUMINA",
    " AND library_strategy=WGS",
    " AND library_source=GENOMIC"
  )

  res <- GET(
    base_url,
    query = list(
      result = "read_run",
      query = query,
      fields = paste(
        c(
          "run_accession",
          "experiment_accession",
          "sample_accession",
          "study_accession",
          "library_strategy",
          "library_source",
          "instrument_model",
          "read_count",
          "base_count",
          "first_public",
          "fastq_ftp"
        ),
        collapse = ","
      ),
      format = "json",
      limit = limit
    )
  )

  if (status_code(res) != 200) return(tibble())

  content(res, as = "parsed", simplifyDataFrame = TRUE) |>
    as_tibble()
}

ena_runs <- taxa_df |>
  mutate(runs = map(taxid, query_ena_isolate_runs)) |>
  unnest(runs)

ena_runs_clean <- ena_runs |>
  filter(
    !is.na(fastq_ftp),
    library_strategy == "WGS",
    library_source == "GENOMIC"
  ) |>
  mutate(
    read_count = as.numeric(read_count),
    base_count = as.numeric(base_count),
    first_public = ymd(first_public)
  )


select_upper_mid <- function(df, n = 6) {
  q <- quantile(
    df$base_count,
    probs = c(0.5, 0.8),
    na.rm = TRUE
  )
  df |>
    filter(
      base_count >= q[1],
      base_count <= q[2]
    ) |>
    arrange(desc(first_public), desc(base_count)) |>
    slice_head(n = n)
}

fallback_top6 <- function(df, n = 6) {
  df |>
    arrange(desc(first_public), desc(base_count)) |>
    slice_head(n = n)
}

top6_runs <- ena_runs_clean |>
  group_by(taxon, study_accession) |>
  arrange(desc(base_count), desc(first_public)) |>
  slice_head(n = 1) |>
  ungroup() |>
  group_by(taxon) |>
  group_modify(~ {
    sel <- select_upper_mid(.x, n = 6)
    if (nrow(sel) < 6) fallback_top6(.x, n = 6) else sel
  }) |>
  ungroup()

top6_runs |>
  group_by(taxon) |>
  summarise(
    n = n(),
    n_studies = length(unique(study_accession)),
    min_date = min(first_public),
    median_bases = median(base_count)
  ) |> print(n=100)

top6_runs |>
pull(run_accession) |>
writeLines("accessions.txt")


top6_runs %>%
  group_by(taxon) %>%
  summarize(Accessions = paste(run_accession, collapse = ", ")) %>%
  write_excel_csv2(file = "table_4_prm.csv")

