#!/bin/bash
set -e

########################################## PREPARE FUNCTIONS ########################################## 
# Source SetUpHCPPipeline.sh to set up pipeline environment variables and software
# Requirements for this script
#  installed versions of FSL 5.0.7 or greater
#  environment: FSLDIR , HCPPIPEDIR , CARET7DIR 
source /home/shared/HCP/taskfmri/phase2/fmri/WORK/GREG_work/HCD_MRFIX_TASK_ANALYSIS/SCRIPTS/SetUpHCPPipeline.sh

source ${HCPPIPEDIR}/global/scripts/log.shlib 			# Logging related functions
source ${HCPPIPEDIR}/global/scripts/fsl_version.shlib 	# Function for getting FSL version

show_tool_versions()
{
	# Show HCP pipelines version
	log_Msg "Showing HCP Pipelines version"
	cat ${HCPPIPEDIR}/version.txt

	# Show wb_command version
	log_Msg "Showing Connectome Workbench (wb_command) version"
	${CARET7DIR}/wb_command -version

	# Show fsl version
	log_Msg "Showing FSL version"
	fsl_version_get fsl_ver
	log_Msg "FSL version: ${fsl_ver}"
}



########################################## READ COMMAND-LINE ARGUMENTS ##################################
g_script_name=`basename ${0}`
log_SetToolName "${g_script_name}"
log_Msg "${g_script_name} arguments: $@"

Subject="$1"
ResultsFolder="$2"
ROIsFolder="$3"
DownSampleFolder="$4"
LevelOnefMRIName="$5"
LevelOnefsfName="$6"
LowResMesh="$7"
GrayordinatesResolution="$8"
OriginalSmoothingFWHM="$9"
Confound="${10}"
FinalSmoothingFWHM="${11}"
TemporalFilter="${12}"
VolumeBasedProcessing="${13}"
RegName="${14}"
Parcellation="${15}"
ParcellationFile="${16}"
AdditionalPreprocessing="${17}"

log_Msg "Subject: ${Subject}"
log_Msg "ResultsFolder: ${ResultsFolder}"
log_Msg "ROIsFolder: ${ROIsFolder}"
log_Msg "DownSampleFolder: ${DownSampleFolder}"
log_Msg "LevelOnefMRIName: ${LevelOnefMRIName}"
log_Msg "LevelOnefsfName: ${LevelOnefsfName}"
log_Msg "LowResMesh: ${LowResMesh}"
log_Msg "GrayordinatesResolution: ${GrayordinatesResolution}"
log_Msg "OriginalSmoothingFWHM: ${OriginalSmoothingFWHM}"
log_Msg "Confound: ${Confound}"
log_Msg "FinalSmoothingFWHM: ${FinalSmoothingFWHM}"
log_Msg "TemporalFilter: ${TemporalFilter}"
log_Msg "VolumeBasedProcessing: ${VolumeBasedProcessing}"
log_Msg "RegName: ${RegName}"
log_Msg "Parcellation: ${Parcellation}"
log_Msg "ParcellationFile: ${ParcellationFile}" 
log_Msg "AdditionalPreprocessing: ${AdditionalPreprocessing}"

show_tool_versions

########################################## MAIN ##################################

if [ ! ${Parcellation} = "NONE" ] ; then
  ParcellationString="_${Parcellation}"
  Extension="ptseries.nii"
else
  ParcellationString=""
  Extension="dtseries.nii"
fi
log_Msg "ParcellationString: ${ParcellationString}"
log_Msg "Extension: ${Extension}"


if [ ! ${RegName} = "NONE" ] ; then
  RegString="_${RegName}"
else
  RegString=""
fi
log_Msg "RegString: ${RegString}"

if [ ${AdditionalPreprocessing} = "FIX" ] ; then
	AdditionalPreprocessingString="_hp2000_clean"
elif [ ${AdditionalPreprocessing} = "NONE" ]; then
	AdditionalPreprocessingString=""
else
	echo "ERROR: Unrecognized AdditionalPreprocessing Option: ${AdditionalPreprocessing}"
	echo ""
	exit 1
fi
log_Msg "AdditionalPreprocessingString: ${AdditionalPreprocessingString}"


#Parcellate data if a Parcellation was provided
log_Msg "Parcellate data if a Parcellation was provided"
if [ ! ${Parcellation} = "NONE" ] ; then
  log_Msg "Parcellating data"
  ${CARET7DIR}/wb_command -cifti-parcellate ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas${RegString}${AdditionalPreprocessingString}.dtseries.nii ${ParcellationFile} COLUMN ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas${RegString}${AdditionalPreprocessingString}${ParcellationString}.ptseries.nii
fi

TR_vol=`${CARET7DIR}/wb_command -file-information ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas${RegString}${AdditionalPreprocessingString}${ParcellationString}.${Extension} -no-map-info -only-step-interval`
log_Msg "TR_vol: ${TR_vol}"

# Only do additional smoothing required to hit the target final smoothing for CIFTI.
# Additional smoothing is not recommended, if looking for area-sized effects use parcellation for greater sensitivity and satistical power
AdditionalSmoothingFWHM=`echo "sqrt(( $FinalSmoothingFWHM ^ 2 ) - ( $OriginalSmoothingFWHM ^ 2 ))" | bc -l`
AdditionalSigma=`echo "$AdditionalSmoothingFWHM / ( 2 * ( sqrt ( 2 * l ( 2 ) ) ) )" | bc -l`
log_Msg "AdditionalSmoothingFWHM: ${AdditionalSmoothingFWHM}"
log_Msg "AdditionalSigma: ${AdditionalSigma}"

SmoothingString="_s${FinalSmoothingFWHM}"
TemporalFilterString="_hp""$TemporalFilter"
log_Msg "SmoothingString: ${SmoothingString}"
log_Msg "TemporalFilterString: ${TemporalFilterString}"

FEATDir="${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefsfName}${AdditionalPreprocessingString}${TemporalFilterString}${SmoothingString}_level1${RegString}${ParcellationString}.feat"
log_Msg "FEATDir: ${FEATDir}"
if [ -e ${FEATDir} ] ; then
  rm -r ${FEATDir}
  mkdir ${FEATDir}
else
  mkdir -p ${FEATDir}
fi

if [ $TemporalFilter = "200" ] ; then
  #Don't edit the fsf file if the temporal filter is the same
  log_Msg "Don't edit the fsf file if the temporal filter is the same"
  cp ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefsfName}_hp200_s4_level1.fsf ${FEATDir}/temp.fsf
else
  #Change the highpass filter string to the desired highpass filter
  log_Msg "Change the highpass filter string to the desired highpass filter"
  cat ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefsfName}_hp200_s4_level1.fsf | sed s/"set fmri(paradigm_hp) \"200\""/"set fmri(paradigm_hp) \"${TemporalFilter}\""/g > ${FEATDir}/temp.fsf
fi

#Change smoothing to be equal to additional smoothing in FSF file and change output directory to match total smoothing and highpass
log_Msg "Change smoothing to be equal to additional smoothing in FSF file and change output directory to match total smoothing and highpass"
cat ${FEATDir}/temp.fsf | sed s/"set fmri(smooth) \"4\""/"set fmri(smooth) \"${AdditionalSmoothingFWHM}\""/g | sed s/_hp200_s4/${AdditionalPreprocessingString}${TemporalFilterString}${SmoothingString}_level1${RegString}${ParcellationString}/g > ${FEATDir}/design.fsf
rm ${FEATDir}/temp.fsf

#Change number of timepoints to match timeseries so that template fsf files can be used
log_Msg "Change number of timepoints to match timeseries so that template fsf files can be used"
fsfnpts=`cat ${FEATDir}/design.fsf | grep "set fmri(npts)" | cut -d " " -f 3 | sed 's/"//g'`
log_Msg "fsfnpts: ${fsfnpts}"
CIFTInpts=`${CARET7DIR}/wb_command -file-information ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas${RegString}${AdditionalPreprocessingString}${ParcellationString}.${Extension} -no-map-info -only-number-of-maps`
log_Msg "CIFTInpts: ${CIFTInpts}"
if [ $fsfnpts -ne $CIFTInpts ] ; then
  cat ${FEATDir}/design.fsf | sed s/"set fmri(npts) \"\?${fsfnpts}\"\?"/"set fmri(npts) ${CIFTInpts}"/g > ${FEATDir}/temp.fsf
  mv ${FEATDir}/temp.fsf ${FEATDir}/design.fsf
  log_Msg "Short Run! Reseting FSF Number of Timepoints (""${fsfnpts}"") to Match CIFTI (""${CIFTInpts}"")"
fi

#Create design files, model confounds if desired
log_Msg "Create design files, model confounds if desired"
DIR=`pwd`
cd ${FEATDir}
if [ $Confound = "NONE" ] ; then
  feat_model ${FEATDir}/design
else 
  feat_model ${FEATDir}/design ${ResultsFolder}/${LevelOnefMRIName}/${Confound}
fi
cd $DIR

#Prepare files and folders
log_Msg "Prepare files and folders"
DesignMatrix=${FEATDir}/design.mat
DesignContrasts=${FEATDir}/design.con
DesignfContrasts=${FEATDir}/design.fts

# An F-test may not always be requested as part of the design.fsf
ExtraArgs=""
if [ -e ${DesignfContrasts} ] ; then
	ExtraArgs="$ExtraArgs --fcon=${DesignfContrasts}"
fi

###CIFTI Processing###
log_Msg "CIFTI Processing"
#Add any additional smoothing, does not do anything if parcellation has been specified. Additional smoothing is not recommended, if looking for area-sized effects use parcellation for greater sensitivity and satistical power
if [[ ! $FinalSmoothingFWHM -eq $OriginalSmoothingFWHM && -z ${ParcellationString} ]] ; then
  ${CARET7DIR}/wb_command -cifti-smoothing ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas${RegString}${AdditionalPreprocessingString}.dtseries.nii ${AdditionalSigma} ${AdditionalSigma} COLUMN ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$SmoothingString"${RegString}${AdditionalPreprocessingString}.dtseries.nii -left-surface "$DownSampleFolder"/"$Subject".L.midthickness."$LowResMesh"k_fs_LR.surf.gii -right-surface "$DownSampleFolder"/"$Subject".R.midthickness."$LowResMesh"k_fs_LR.surf.gii
else
  cp ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas${RegString}${AdditionalPreprocessingString}${ParcellationString}.${Extension} ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$SmoothingString"${RegString}${AdditionalPreprocessingString}${ParcellationString}.${Extension}
fi

#Add temporal filtering
log_Msg "Add temporal filtering"
${CARET7DIR}/wb_command -cifti-convert -to-nifti ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$SmoothingString"${RegString}${AdditionalPreprocessingString}${ParcellationString}.${Extension} ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$SmoothingString"${RegString}${AdditionalPreprocessingString}${ParcellationString}_FAKENIFTI.nii.gz
fslmaths ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$SmoothingString"${RegString}${AdditionalPreprocessingString}${ParcellationString}_FAKENIFTI.nii.gz -Tmean ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$SmoothingString"${RegString}${AdditionalPreprocessingString}${ParcellationString}_FAKENIFTI_mean.nii.gz
fslmaths ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$SmoothingString"${RegString}${AdditionalPreprocessingString}${ParcellationString}_FAKENIFTI.nii.gz -bptf `echo "0.5 * $TemporalFilter / $TR_vol" | bc -l` 0 -add ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$SmoothingString"${RegString}${AdditionalPreprocessingString}${ParcellationString}_FAKENIFTI_mean.nii.gz ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$SmoothingString"${RegString}${AdditionalPreprocessingString}${ParcellationString}_FAKENIFTI.nii.gz
${CARET7DIR}/wb_command -cifti-convert -from-nifti ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$SmoothingString"${RegString}${AdditionalPreprocessingString}${ParcellationString}_FAKENIFTI.nii.gz ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$SmoothingString"${RegString}${AdditionalPreprocessingString}${ParcellationString}.${Extension} ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$TemporalFilterString""$SmoothingString"${RegString}${AdditionalPreprocessingString}${ParcellationString}.${Extension}
rm ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$SmoothingString"${RegString}${AdditionalPreprocessingString}${ParcellationString}_FAKENIFTI.nii.gz ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$SmoothingString"${RegString}${AdditionalPreprocessingString}${ParcellationString}_FAKENIFTI_mean.nii.gz

#Check if data are Parcellated, if not, do Dense Grayordinates Analysis#
log_Msg "Check if data are Parcellated, if not, do Dense Grayordinates Analysis"
if [ -z ${ParcellationString} ] ; then

  ###Dense Grayordinates Processing###
  log_Msg "Dense Grayordinates Processing"
  #Split into surface and volume
  log_Msg "Split into surface and volume"
  ${CARET7DIR}/wb_command -cifti-separate-all ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$TemporalFilterString""$SmoothingString"${RegString}${AdditionalPreprocessingString}.dtseries.nii -volume ${FEATDir}/${LevelOnefMRIName}_AtlasSubcortical"$TemporalFilterString""$SmoothingString".nii.gz -left ${FEATDir}/${LevelOnefMRIName}${TemporalFilterString}${SmoothingString}${RegString}${AdditionalPreprocessingString}.atlasroi.L."$LowResMesh"k_fs_LR.func.gii -right ${FEATDir}/${LevelOnefMRIName}${TemporalFilterString}${SmoothingString}${RegString}${AdditionalPreprocessingString}.atlasroi.R."$LowResMesh"k_fs_LR.func.gii

  #Run film_gls on subcortical volume data
  log_Msg "Run film_gls on subcortical volume data"
  film_gls --rn=${FEATDir}/SubcorticalVolumeStats --sa --ms=5 --in=${FEATDir}/${LevelOnefMRIName}_AtlasSubcortical"$TemporalFilterString""$SmoothingString".nii.gz --pd="$DesignMatrix" --con=${DesignContrasts} ${ExtraArgs} --thr=1 --mode=volumetric
  rm ${FEATDir}/${LevelOnefMRIName}_AtlasSubcortical"$TemporalFilterString""$SmoothingString".nii.gz

  #Run film_gls on cortical surface data 
  log_Msg "Run film_gls on cortical surface data"
  for Hemisphere in L R ; do
    #Prepare for film_gls. Some smoothing is done when calculating the prewhitening. The medial wall is empty in the GIFTI image, so a metric-dilate is done to avoid smoothing null data into the signal.
	log_Msg "Prepare for film_gls"
    ${CARET7DIR}/wb_command -metric-dilate ${FEATDir}/${LevelOnefMRIName}${TemporalFilterString}${SmoothingString}${RegString}${AdditionalPreprocessingString}.atlasroi."$Hemisphere"."$LowResMesh"k_fs_LR.func.gii "$DownSampleFolder"/"$Subject"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii 50 ${FEATDir}/${LevelOnefMRIName}${TemporalFilterString}${SmoothingString}${RegString}${AdditionalPreprocessingString}.atlasroi_dil."$Hemisphere"."$LowResMesh"k_fs_LR.func.gii -nearest

    #Run film_gls on surface data
    log_Msg "Run film_gls on surface data"
    film_gls --rn=${FEATDir}/"$Hemisphere"_SurfaceStats --sa --ms=15 --epith=5 --in2="$DownSampleFolder"/"$Subject"."$Hemisphere".midthickness."$LowResMesh"k_fs_LR.surf.gii --in=${FEATDir}/${LevelOnefMRIName}${TemporalFilterString}${SmoothingString}${RegString}${AdditionalPreprocessingString}.atlasroi_dil."$Hemisphere"."$LowResMesh"k_fs_LR.func.gii --pd="$DesignMatrix" --con=${DesignContrasts} ${ExtraArgs} --mode=surface
    rm ${FEATDir}/${LevelOnefMRIName}${TemporalFilterString}${SmoothingString}${RegString}${AdditionalPreprocessingString}.atlasroi_dil."$Hemisphere"."$LowResMesh"k_fs_LR.func.gii ${FEATDir}/${LevelOnefMRIName}${TemporalFilterString}${SmoothingString}${RegString}${AdditionalPreprocessingString}.atlasroi."$Hemisphere"."$LowResMesh"k_fs_LR.func.gii
  done

  #Merge Cortical Surface and Subcortical Volume into Grayordinates
  log_Msg "Merge Cortical Surface and Subcortical Volume into Grayordinates"
  mkdir ${FEATDir}/GrayordinatesStats
  cat ${FEATDir}/SubcorticalVolumeStats/dof > ${FEATDir}/GrayordinatesStats/dof
  cat ${FEATDir}/SubcorticalVolumeStats/logfile > ${FEATDir}/GrayordinatesStats/logfile
  cat ${FEATDir}/L_SurfaceStats/logfile >> ${FEATDir}/GrayordinatesStats/logfile
  cat ${FEATDir}/R_SurfaceStats/logfile >> ${FEATDir}/GrayordinatesStats/logfile
  cd ${FEATDir}/SubcorticalVolumeStats
  Files=`ls | grep .nii.gz | cut -d "." -f 1`
  cd $DIR
  for File in $Files ; do
    ${CARET7DIR}/wb_command -cifti-create-dense-timeseries ${FEATDir}/GrayordinatesStats/${File}.dtseries.nii -volume ${FEATDir}/SubcorticalVolumeStats/${File}.nii.gz $ROIsFolder/Atlas_ROIs.${GrayordinatesResolution}.nii.gz -left-metric ${FEATDir}/L_SurfaceStats/${File}.func.gii -roi-left "$DownSampleFolder"/"$Subject".L.atlasroi."$LowResMesh"k_fs_LR.shape.gii -right-metric ${FEATDir}/R_SurfaceStats/${File}.func.gii -roi-right "$DownSampleFolder"/"$Subject".R.atlasroi."$LowResMesh"k_fs_LR.shape.gii
  done
  rm -r ${FEATDir}/SubcorticalVolumeStats ${FEATDir}/L_SurfaceStats ${FEATDir}/R_SurfaceStats

else

  ###Parcellated Processing###
  log_Msg "Parcellated Processing"
  ${CARET7DIR}/wb_command -cifti-convert -to-nifti ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$TemporalFilterString""$SmoothingString"${RegString}${AdditionalPreprocessingString}${ParcellationString}.${Extension} ${FEATDir}/${LevelOnefMRIName}_Atlas"$TemporalFilterString""$SmoothingString"${RegString}${AdditionalPreprocessingString}${ParcellationString}_FAKENIFTI.nii.gz
  film_gls --rn=${FEATDir}/ParcellatedStats --in=${FEATDir}/${LevelOnefMRIName}_Atlas"$TemporalFilterString""$SmoothingString"${RegString}${AdditionalPreprocessingString}${ParcellationString}_FAKENIFTI.nii.gz --pd="$DesignMatrix" --con=${DesignContrasts} ${ExtraArgs} --thr=1 --mode=volumetric
  rm ${FEATDir}/${LevelOnefMRIName}_Atlas"$TemporalFilterString""$SmoothingString"${RegString}${AdditionalPreprocessingString}${ParcellationString}_FAKENIFTI.nii.gz
  cd ${FEATDir}/ParcellatedStats
  Files=`ls | grep .nii.gz | cut -d "." -f 1`
  cd $DIR
  for File in $Files ; do
    ${CARET7DIR}/wb_command -cifti-convert -from-nifti ${FEATDir}/ParcellatedStats/${File}.nii.gz ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_Atlas"$TemporalFilterString""$SmoothingString"${RegString}${AdditionalPreprocessingString}${ParcellationString}.ptseries.nii ${FEATDir}/ParcellatedStats/${File}.ptseries.nii -reset-timepoints 1 1
  done
  rm ${FEATDir}/ParcellatedStats/*.nii.gz
fi

###Standard NIFTI Volume-based Processsing###
if [ $VolumeBasedProcessing = "YES" ] ; then
  log_Msg "Standard NIFTI Volume-based Processsing"
  #Add volume smoothing
  log_Msg "Add volume smoothing"
  FinalSmoothingSigma=`echo "$FinalSmoothingFWHM / ( 2 * ( sqrt ( 2 * l ( 2 ) ) ) )" | bc -l`
  fslmaths ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_SBRef.nii.gz -bin -kernel gauss ${FinalSmoothingSigma} -fmean ${FEATDir}/mask_weight -odt float
  fslmaths ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}${AdditionalPreprocessingString}.nii.gz -kernel gauss ${FinalSmoothingSigma} -fmean -div ${FEATDir}/mask_weight -mas ${ResultsFolder}/${LevelOnefMRIName}/${LevelOnefMRIName}_SBRef.nii.gz ${FEATDir}/${LevelOnefMRIName}${AdditionalPreprocessingString}"$SmoothingString".nii.gz -odt float
  
  #Add temporal filtering
  log_Msg "Add temporal filtering"
  fslmaths ${FEATDir}/${LevelOnefMRIName}${AdditionalPreprocessingString}"$SmoothingString".nii.gz -bptf `echo "0.5 * $TemporalFilter / $TR_vol" | bc -l` -1 ${FEATDir}/${LevelOnefMRIName}${AdditionalPreprocessingString}"$TemporalFilterString""$SmoothingString".nii.gz

  #Run film_gls on subcortical volume data
  log_Msg "Run film_gls on subcortical volume data"
  film_gls --rn=${FEATDir}/StandardVolumeStats --sa --ms=5 --in=${FEATDir}/${LevelOnefMRIName}${AdditionalPreprocessingString}"$TemporalFilterString""$SmoothingString".nii.gz --pd="$DesignMatrix" --con=${DesignContrasts} ${ExtraArgs} --thr=1000
fi


