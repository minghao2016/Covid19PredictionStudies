
#' Execute the validation study
#'
#' @details
#' This function will execute the sepcified parts of the study
#'
#' @param connectionDetails    An object of type \code{connectionDetails} as created using the
#'                             \code{\link[DatabaseConnector]{createConnectionDetails}} function in the
#'                             DatabaseConnector package.
#' @param databaseName         A string representing a shareable name of your databasd
#' @param cdmDatabaseSchema    Schema name where your patient-level data in OMOP CDM format resides.
#'                             Note that for SQL Server, this should include both the database and
#'                             schema name, for example 'cdm_data.dbo'.
#' @param cohortDatabaseSchema Schema name where intermediate data can be stored. You will need to have
#'                             write priviliges in this schema. Note that for SQL Server, this should
#'                             include both the database and schema name, for example 'cdm_data.dbo'.
#' @param oracleTempSchema     Should be used in Oracle to specify a schema where the user has write
#'                             priviliges for storing temporary tables.
#' @param cohortTable          The name of the table that will be created in the work database schema.
#'                             This table will hold the exposure and outcome cohorts used in this
#'                             study.
#' @param outputFolder         Name of local folder to place results; make sure to use forward slashes
#'                             (/)
#' @param createCohorts        Whether to create the cohorts for the study
#' @param runValidation        Whether to run the valdiation models
#' @param packageResults       Whether to package the results (after removing sensitive details)
#' @param minCellCount         The min count for the result to be included in the package results
#' @param sampleSize           Whether to sample from the target cohort - if desired add the number to sample
#' @param keepPrediction       Whether to save the individual predictions
#' @param verbosity            Log verbosity
#' @export
execute <- function(connectionDetails,
                    databaseName,
                    cdmDatabaseSchema,
                    cohortDatabaseSchema,
                    oracleTempSchema,
                    cohortTable,
                    outputFolder,
                    cdmVersion = 5,
                    endDay = -1,
                    riskWindowStart = 2,
                    startAnchor = 'cohort start',
                    riskWindowEnd = 30,
                    endAnchor = 'cohort start',
                    firstExposureOnly = F,
                    removeSubjectsWithPriorOutcome = F,
                    priorOutcomeLookback = 1,
                    requireTimeAtRisk = F,
                    minTimeAtRisk = 1,
                    includeAllOutcomes = T,
                    usePackageCohorts = T,
                    createCohorts = T,
                    runValidation = T,
                    runSimple = F,
                    predictSevereAtOutpatientVisit = F,
                    packageResults = T,
                    minCellCount = 5,
                    sampleSize = NULL,
                    keepPrediction = T,
                    verbosity = 'INFO'){

  if (!file.exists(outputFolder))
    dir.create(outputFolder, recursive = TRUE)

  ParallelLogger::addDefaultFileLogger(file.path(outputFolder,databaseName, "log.txt"))

  if(createCohorts){
    ParallelLogger::logInfo("Creating Cohorts")
    createCohorts(connectionDetails,
                  cdmDatabaseSchema=cdmDatabaseSchema,
                  cohortDatabaseSchema=cohortDatabaseSchema,
                  cohortTable=cohortTable,
                  oracleTempSchema = oracleTempSchema,
                  outputFolder = file.path(outputFolder,databaseName))
  }

  if(runValidation){
    ParallelLogger::logInfo("Validating Models")
    # for each model externally validate
    analysesLocation <- system.file("plp_models",
                                    package = "SentHomeValidation")
    val <- PatientLevelPrediction::evaluateMultiplePlp(analysesLocation = analysesLocation,
                                                       outputLocation = outputFolder,
                                                       connectionDetails = connectionDetails,
                                                       validationSchemaTarget = cohortDatabaseSchema,
                                                       validationSchemaOutcome = cohortDatabaseSchema,
                                                       validationSchemaCdm = cdmDatabaseSchema,
                                                       oracleTempSchema = oracleTempSchema,
                                                       databaseNames = databaseName,
                                                       validationTableTarget = cohortTable,
                                                       validationTableOutcome = cohortTable,
                                                       sampleSize = sampleSize,
                                                       keepPrediction = keepPrediction,
                                                       verbosity = verbosity)
  }

if(runSimple){
  standardCovariates <- FeatureExtraction::createCovariateSettings(useDemographicsAgeGroup = T,
                                                                   useDemographicsGender = T,
                                                                   excludedCovariateConceptIds = 8532 )
    studyAnalyses <- getSettings(predictSevereAtOutpatientVisit = predictSevereAtOutpatientVisit,
                                 usePackageCohorts = usePackageCohorts)
    if( nrow(studyAnalyses)!=0){
      if( nrow(studyAnalyses)!=0){
      for(k in 1:nrow(studyAnalyses)){
        sa <- studyAnalyses[k,]
        result <- predictSimple(connectionDetails = connectionDetails,
                                cohortId = sa$cohortId,
                                outcomeIds = sa$outcomeId,
                                model = sa$model,
                                analysisId = sa$analysisId,
                                studyStartDate = sa$studyStartDate,
                                studyEndDate = sa$studyEndDate,
                                cdmDatabaseSchema = cdmDatabaseSchema,
                                cdmDatabaseName = databaseName,
                                cohortDatabaseSchema = cohortDatabaseSchema,
                                cohortTable = cohortTable,
                                oracleTempSchema = oracleTempSchema,
                                standardCovariates = standardCovariates,
                                endDay = endDay,
                                sampleSize = sampleSize,
                                cdmVersion = cdmVersion,
                                riskWindowStart = riskWindowStart,
                                startAnchor = startAnchor,
                                riskWindowEnd = riskWindowEnd,
                                endAnchor = endAnchor,
                                firstExposureOnly = firstExposureOnly,
                                removeSubjectsWithPriorOutcome = removeSubjectsWithPriorOutcome,
                                priorOutcomeLookback = priorOutcomeLookback,
                                requireTimeAtRisk = requireTimeAtRisk,
                                minTimeAtRisk = minTimeAtRisk,
                                includeAllOutcomes = includeAllOutcomes)


        if(!is.null(result)){
          if(!dir.exists(file.path(outputFolder,databaseName, paste0('Analysis_',sa$analysisId)))){
            dir.create(file.path(outputFolder,databaseName,paste0('Analysis_',sa$analysisId)), recursive = T)
          }
          ParallelLogger::logInfo("Saving results")
          saveRDS(result, file.path(outputFolder,databaseName,paste0('Analysis_',sa$analysisId),'validationResults.rds'))
          ParallelLogger::logInfo(paste0("Results saved to:",file.path(outputFolder,databaseName,paste0('Analysis_',sa$analysisId),'validationResults.rds')))
        }
      }
      }
    }
}
  # package the results: this creates a compressed file with sensitive details removed - ready to be reviewed and then
  # submitted to the network study manager

  # results saved to outputFolder/databaseName
  if (packageResults) {
    ParallelLogger::logInfo("Packaging results")
    packageResults(outputFolder = file.path(outputFolder,databaseName),
                   minCellCount = minCellCount)
  }


  invisible(NULL)

}
