#!/usr/bin/env Rscript

options(stringsAsFactors=F)
#options(warn=2) 
options(error = quote({
  dump.frames(to.file=T, dumpto='last.dump')
  load('last.dump.rda')
  print(last.dump)
  q()
}))

args = commandArgs(trailingOnly=TRUE)

variant_summary_table = 'variant_summary.txt.gz'
if (length(args) != 3) {
  print(paste("Requires 3 command line args: [variant_summary table] [clinvar_allele_trait_pairs table] [output_table_path]",multi))
  exit(-1)
}

variant_summary_table = gzfile(args[1])
clinvar_allele_trait_pairs_table = gzfile(args[2])
output_table = gzfile(args[3], 'w')


# load what we've extracted from the XML so far
xml_raw = read.table(clinvar_allele_trait_pairs_table, sep='\t', comment.char='', quote='', header=T, skipNul=T, check.names=F)
print(dim(xml_raw))

# load the tab-delimited summary
txt_download = read.table(variant_summary_table, sep='\t', comment.char='', quote='', header=T, skipNul=T, check.names=F)
print(dim(txt_download))

# subset the tab-delimited summary to desired rows and cols
colnames(txt_download) = gsub('\\.','_',tolower(colnames(txt_download)))
colnames(txt_download) = replace(colnames(txt_download), 1, "allele_id")

desired_columns<-c('allele_id','clinicalsignificance','reviewstatus','lastevaluated')
txt_extract = subset(txt_download, assembly == 'GRCh37', select=desired_columns)
colnames(txt_extract)<-c('allele_id','clinical_significance','review_status','last_evaluated')
#drop the clinical_significance and review_status in clinvar_record.tsv 
#use the summary ones in variant_summary.txt
xml_extract = subset(xml_raw,select=-c(clinical_significance,review_status))

# join on allele id
combined = merge(xml_extract, txt_extract,by='allele_id',all.x=FALSE)

# lookup table based on http://www.ncbi.nlm.nih.gov/clinvar/docs/details/
gold_stars_table = list(
  'no assertion provided' = 0,
  'no assertion for the individual variant' = 0,
  'no assertion criteria provided' = 0,
  'criteria provided, single submitter' = 1,
  'criteria provided, conflicting interpretations' = 1, 
  'criteria provided, multiple submitters, no conflicts' = 2, 
  'reviewed by expert panel' = 3,
  'practice guideline' = 4
)

# add some layers of interpretation on top of this
# note: we are trying to get the "overall" interpretation that is displayed in the upper right of the clinvar web pages but
# it is not in any of the available FTP downloads, so this is a stopgap
combined$gold_stars = sapply(combined$review_status, function(k) { gold_stars_table[[k]] })

# pathogenic = 1 if at least one submission says path or likely path, 0 otherwise
combined$pathogenic = as.integer(grepl('athogenic',combined$clinical_significance))

# conflicted = 1 if at least one submission each of [likely] benign and [likely] pathogenic
combined$conflicted = as.integer(grepl('athogenic',combined$clinical_significance) & grepl('enign',combined$clinical_significance))

# benign = 1 if at least one submission says benign or likely benign, 0 otherwise
combined$benign = as.integer(grepl('enign',combined$clinical_significance))

# re-order the columns
combined = combined[,c('chrom','pos','ref','alt','measureset_type','measureset_id','rcv','allele_id','symbol', 'hgvs_c','hgvs_p','molecular_consequence','clinical_significance', 'pathogenic', 'benign', 'conflicted', 'review_status','last_evaluated', 'gold_stars','all_submitters','all_traits','all_pmids', 'inheritance_modes', 'age_of_onset','prevalence', 'disease_mechanism', 'origin', 'xrefs')]

write.table(combined, output_table, sep='\t', row.names=F, col.names=T, quote=F)

close(output_table)
