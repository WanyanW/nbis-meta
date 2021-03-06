from snakemake.utils import min_version, validate
from snakemake.exceptions import WorkflowError
min_version("4.4.0")

# Snakemake workflow for various types of metagenomics analyses.
# See documentation at https://bitbucket.org/scilifelab-lts/nbis-meta

def parse_validation_error(e):
    instance = ""
    print("ERROR VALIDATING CONFIG FILE")
    for item in str(e).split("\n"):
        item = item.replace('"','')
        if "ValidationError:" in item:
            print(item)
        if item[0:11] == "On instance":
            instance = item.replace("On instance['", "INCORRECT CONFIG AT: ")
            instance = instance.replace("']:","")
            print(instance)
    return

shell.prefix("")
configfile: "config.yaml"
# Handle cases where user does not enter min_contig_length as an array
if type(config["min_contig_length"]) != list:
    config["min_contig_length"] = [config["min_contig_length"]]
try:
    validate(config, "config/config.schema.yaml")
except WorkflowError as e:
    parse_validation_error(e)
    sys.exit()
workdir: config["workdir"]

# First load init file to set up samples and variables
include: "source/init/init.smk"
pipeline_report = config["pipeline_config_file"]

#############
## Targets ##
#############
inputs = [pipeline_report]
# Download and format databases for annotation
db_input = []
include: "source/workflow/DB"
inputs += db_input
# Preprocess raw input (if no preprocessing, just produce the sample report for raw data)
preprocess_input = []
include: "source/workflow/Preprocess"
inputs += preprocess_input
# Assemble
assembly_input = []
annotation_input = []
binning_input = []
if config["assembly"]:
    include: "source/workflow/Assembly"
    inputs += assembly_input
    # Rule sets that depend on de-novo assembly
    # Annotate
    if config["annotation"]:
        include: "source/workflow/Annotation"
        inputs += annotation_input
    # Binning
    if config["maxbin"] or config["concoct"] or config["metabat"]:
        include: "source/workflow/Binning"
        inputs += binning_input
# Kraken
kraken_input = []
kraken_db_input = []
if config["kraken"]:
    # Download and process kraken datatbase
    include: "source/workflow/KrakenDB"
    # Kraken classify samples
    include: "source/workflow/KrakenClassify"
    inputs += kraken_input + kraken_db_input
# Metaphlan2
metaphlan_input = []
metaphlan_db_input = []
if config["metaphlan2"]:
    include: "source/workflow/Metaphlan2DB"
    include: "source/workflow/Metaphlan2Classify"
    inputs += metaphlan_input + metaphlan_db_input
# Centrifuge
centrifuge_input = []
centrifuge_db_input = []
if config["centrifuge"]:
    include: "source/workflow/CentrifugeDB"
    include: "source/workflow/CentrifugeClassify"
    inputs += centrifuge_input + centrifuge_db_input
# Reference-based mapping
map_input = []
if config["reference_map"]:
    # Use centrifuge to download genomes for reference mapping
    # So set run_centrifuge to True
    config["centrifuge"] = True
    include: "source/workflow/Map"
    inputs += map_input

###########
## RULES ##
###########
# master target rule
rule all:
    input: inputs

# db target rule
rule db:
  input: db_input

# preprocess target rule
rule preprocess:
    input: pipeline_report, preprocess_input

# assembly target rule
rule assembly:
    input: pipeline_report, preprocess_input, assembly_input

# annotation target rule
rule annotation:
    input: pipeline_report, preprocess_input, db_input, assembly_input, annotation_input

# centrifuge
rule centrifuge_db:
    input: centrifuge_db_input
rule centrifuge_classify:
    input: pipeline_report, preprocess_input, centrifuge_input

# kraken
rule kraken_db:
    input: kraken_db_input
rule kraken_classify:
    input: pipeline_report, preprocess_input, kraken_input

# metaphlan2
rule metaphlan2_db:
    input: metaphlan_db_input
rule metaphlan2_classify:
    input: pipeline_report, preprocess_input, metaphlan_db_input, metaphlan_input

# binning
rule binning:
    input: pipeline_report, preprocess_input, assembly_input, binning_input

# Reference based database
rule refmap:
    input: pipeline_report, centrifuge_db_input, preprocess_input, map_input
