#!/bin/bash
#
# Retrieve CMIP7 forcing data using esgpull
#
# See README.md for instructions on how to install esgpull etc.
#
# IMPORTANT: Currently, this only works if esgpull is set to search an index node.
# To set this up:
# esgpull config api.index_node esgf-node.ornl.gov/esgf-1-5-bridge
# See: https://github.com/ESGF/esgf-download/issues/101
#
# Usage:
#   ./esgpull_cmip7.sh                 # fetch the datasets switched on below
#   ./esgpull_cmip7.sh solar ghg_conc  # fetch only the named datasets
#
# Available names: solar ghg_conc o3 amip simple_plumes strat_aerosols
#                  emissions ndep pop_dens
#
# Author: Joakim Kjellsson, September 2025
#

# Defaults: set the ones you want to 1, others to 0
solar=0
ghg_conc=0
o3=0
amip=0
simple_plumes=0
strat_aerosols=0
emissions=0
ndep=0
pop_dens=0

PROJECT="input4MIPs"
MIP_ERA="CMIP7"

# Due to a bug in esgpull, the source_id should be wrapped in literal quotation
# marks. Set to 0 to pass source_id unquoted.
QUOTE_SOURCE_ID=1

# If command-line arguments are given, they override the defaults above
if [ $# -gt 0 ] ; then
    solar=0 ; ghg_conc=0 ; o3=0 ; amip=0 ; simple_plumes=0
    strat_aerosols=0 ; emissions=0 ; ndep=0 ; pop_dens=0
    for name in "$@" ; do
        case "${name}" in
            solar|ghg_conc|o3|amip|simple_plumes|strat_aerosols|emissions|ndep|pop_dens)
                declare "${name}=1" ;;
            *)
                echo "Unknown dataset: ${name}" >&2 ; exit 1 ;;
        esac
    done
fi

#
# Generic function: search, track, update and download one source_id
# (optionally restricted to one variable_id) from ESGF using esgpull.
#
# Usage: get_esgf_data SOURCE_ID [VARIABLE_ID]
#
get_esgf_data() {
    local source_id="$1"
    local variable_id="${2:-}"

    # The tag never contains quotes, even if the query does
    local tag="cmip7-${source_id}"
    [ -n "${variable_id}" ] && tag="${tag}-${variable_id}"

    local sid="${source_id}"
    [ "${QUOTE_SOURCE_ID}" == "1" ] && sid="\"${source_id}\""

    local query=("project:${PROJECT}" "mip_era:${MIP_ERA}" "source_id:${sid}")
    [ -n "${variable_id}" ] && query+=("variable_id:${variable_id}")

    # search and list data
    echo "esgpull search ${query[*]}"
    esgpull search "${query[@]}"

    # track data
    echo "esgpull add --tag ${tag} --track ${query[*]}"
    esgpull add --tag "${tag}" --track "${query[@]}"

    # if the search has been done before, update it in case of new data
    esgpull update -y --tag "${tag}"

    # download data
    esgpull download --tag "${tag}"
}

#
# Helper: fetch every source_id in a list, optionally for a list of variables
#
# Usage: get_esgf_list "source_id1 source_id2 ..." ["var1 var2 ..."]
#
get_esgf_list() {
    local source_ids="$1"
    local variable_ids="${2:-}"
    local source_id variable_id

    for source_id in ${source_ids} ; do
        if [ -z "${variable_ids}" ] ; then
            get_esgf_data "${source_id}"
        else
            for variable_id in ${variable_ids} ; do
                get_esgf_data "${source_id}" "${variable_id}"
            done
        fi
    done
}

#
# Solar forcing (historical and scenario)
#
if [ "${solar}" == "1" ] ; then
    get_esgf_list "SOLARIS-HEPPA-CMIP-4-6 SOLARIS-HEPPA-ScenarioMIP-4-6"
fi

#
# Greenhouse-gas concentrations (DECK + ScenarioMIP scenarios)
# We don't want it all, just some GHGs for now
#
if [ "${ghg_conc}" == "1" ] ; then
    ghg_sources="CR-CMIP-1-0-0"
    for scen in vl ml m ln l hl h ; do
        ghg_sources="${ghg_sources} CR-${scen}-ext-1-1-0 CR-${scen}-1-1-0"
    done
    get_esgf_list "${ghg_sources}" "cfc11eq cfc12 ch4 co2 n2o"
fi

#
# Ozone concentrations
# NOTE: There are problems with this data.
# Current recommendation is to use the v1.2 climatology file for piControl
# but v2.0 files for historical, so we need both.
#
if [ "${o3}" == "1" ] ; then
    get_esgf_list "FZJ-CMIP-ozone-1-2 FZJ-CMIP-ozone-2-0 FZJ-CMIP-ozone-vl-1-0 FZJ-CMIP-ozone-h-1-0"
fi

#
# AMIP SST and sea ice
#
if [ "${amip}" == "1" ] ; then
    get_esgf_list "PCMDI-AMIP-1-1-10"
fi

#
# Simple plumes (MACv2-SP). Not on ESGF yet, so get from Zenodo.
#
if [ "${simple_plumes}" == "1" ] ; then
    wget https://zenodo.org/records/15283189/files/SPv2.1_1850-2023_CMIP7.nc

    # scenarios
    wget https://zenodo.org/records/18713154/files/Simple_plumes_SPv2.1_CMIP7_h_scenario.nc
    wget https://zenodo.org/records/18713154/files/Simple_plumes_SPv2.1_CMIP7_vl_scenario.nc

    mkdir -vp macv2sp
    mv SPv2.1_1850-2023_CMIP7.nc Simple_plumes_SPv2.1_CMIP7*.nc macv2sp/.
fi

#
# Stratospheric aerosols
#
if [ "${strat_aerosols}" == "1" ] ; then
    get_esgf_list "UOEXETER-CMIP-2-2-1 UOEXETER-ScenarioMIP-2-2-2"
fi

#
# Emissions
#
if [ "${emissions}" == "1" ] ; then
    get_esgf_list "CEDS-CMIP-2025-04-18 CEDS-CMIP-2025-04-18-supplemental"
fi

#
# Population density: PIK-CMIP-1-0-1 (DECK) and ScenarioMIP scenarios
#
if [ "${pop_dens}" == "1" ] ; then
    pop_sources="PIK-CMIP-1-0-1"
    for scen in vl ln l ml m hl h ; do
        pop_sources="${pop_sources} PIK-${scen}-1-0-0"
    done
    get_esgf_list "${pop_sources}"
fi

#
# Nitrogen deposition
#
if [ "${ndep}" == "1" ] ; then
    get_esgf_list "FZJ-CMIP-nitrogen-1-2"
fi
