# Copyright 2020 Observational Health Data Sciences and Informatics
#
# This file is part of CovidSimpleModels
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

.createCohorts <- function(connection,
                           cdmDatabaseSchema,
                           vocabularyDatabaseSchema = cdmDatabaseSchema,
                           cohortDatabaseSchema,
                           cohortTable,
                           oracleTempSchema,
                           usePackageCohorts = T,
                           newTargetCohortId = 1,
                           newOutcomeCohortId = 2,
                           newCohortDatabaseSchema = '',
                           newCohortTable = 'cohort',
                           outputFolder) {
  
  # Create study cohort table structure:
  sql <- SqlRender::loadRenderTranslateSql(sqlFilename = "CreateCohortTable.sql",
                                           packageName = "CovidSimpleModels",
                                           dbms = attr(connection, "dbms"),
                                           oracleTempSchema = oracleTempSchema,
                                           cohort_database_schema = cohortDatabaseSchema,
                                           cohort_table = cohortTable)
  DatabaseConnector::executeSql(connection, sql, progressBar = FALSE, reportOverallTime = FALSE)
  
  
  
  # Instantiate cohorts:
  if(usePackageCohorts){
    pathToCsv <- system.file("settings", "CohortsToCreate.csv", package = "CovidSimpleModels")
    cohortsToCreate <- utils::read.csv(pathToCsv)
    for (i in 1:nrow(cohortsToCreate)) {
      writeLines(paste("Creating cohort:", cohortsToCreate$name[i]))
      sql <- SqlRender::loadRenderTranslateSql(sqlFilename = paste0(cohortsToCreate$name[i], ".sql"),
                                               packageName = "CovidSimpleModels",
                                               dbms = attr(connection, "dbms"),
                                               oracleTempSchema = oracleTempSchema,
                                               cdm_database_schema = cdmDatabaseSchema,
                                               vocabulary_database_schema = vocabularyDatabaseSchema,
                                               
                                               target_database_schema = cohortDatabaseSchema,
                                               target_cohort_table = cohortTable,
                                               target_cohort_id = cohortsToCreate$cohortId[i])
      DatabaseConnector::executeSql(connection, sql)
    }
  } else {
    # copy the tables over to the new cohort table...
    ParallelLogger::logInfo('Inserting the new target cohort into table')
    sql <- "DELETE FROM @cohort_database_schema.@cohort_table where cohort_definition_id = 1;
    insert into @cohort_database_schema.@cohort_table(cohort_definition_id, subject_id, cohort_start_date, cohort_end_date) 
    select 1 as cohort_definition_id, subject_id, cohort_start_date, cohort_end_date 
    from @new_cohort_database_schema.@new_cohort_table where cohort_definition_id = @cohort_definition_id;"
    sql <- SqlRender::render(sql = sql, 
                                cohort_database_schema = cohortDatabaseSchema,
                                cohort_table = cohortTable,
                                new_cohort_database_schema = newCohortDatabaseSchema,
                                new_cohort_table = newCohortTable, 
                                cohort_definition_id = newTargetCohortId)
    sql <- SqlRender::translate(sql = sql,
                                oracleTempSchema = oracleTempSchema, 
                                targetDialect = attr(connection, "dbms"))
    DatabaseConnector::executeSql(connection, sql)
    
    ParallelLogger::logInfo('Inserting the new outcome cohort into table')
    sql <- "DELETE FROM @cohort_database_schema.@cohort_table where cohort_definition_id = 2;
    insert into @cohort_database_schema.@cohort_table (cohort_definition_id, subject_id, cohort_start_date, cohort_end_date) 
    select 2 as cohort_definition_id, subject_id, cohort_start_date, cohort_end_date 
    from @new_cohort_database_schema.@new_cohort_table where cohort_definition_id = @cohort_definition_id;"
    sql <- SqlRender::render(sql = sql, 
                                cohort_database_schema = cohortDatabaseSchema,
                                cohort_table = cohortTable,
                                new_cohort_database_schema = newCohortDatabaseSchema,
                                new_cohort_table = newCohortTable, 
                                cohort_definition_id = newOutcomeCohortId)
    sql <- SqlRender::translate(sql = sql, 
                                oracleTempSchema = oracleTempSchema, 
                                targetDialect = attr(connection, "dbms"))
    DatabaseConnector::executeSql(connection, sql)
  }
  
  pathToCustom <- system.file("settings", 'CustomCovariates.csv', package = "CovidSimpleModels")
  if(file.exists(pathToCustom)){
    # if custom cohort covaraites set:
    cohortVarsToCreate <- utils::read.csv(pathToCustom)
    
    if(sum(colnames(cohortVarsToCreate)%in%c('atlasId', 'cohortName', 'startDay', 'endDay'))!=4){
      stop('Issue with cohortVariableSetting - make sure it is NULL or a setting')  
    }
    
    cohortVarsToCreate <- unique(cohortVarsToCreate[,c('atlasId', 'cohortName')])
    for (i in 1:nrow(cohortVarsToCreate)) {
      writeLines(paste("Creating cohort:", cohortVarsToCreate$cohortName[i]))
      sql <- SqlRender::loadRenderTranslateSql(sqlFilename = paste0(cohortVarsToCreate$cohortName[i], ".sql"),
                                               packageName = "CovidSimpleModels",
                                               dbms = attr(connection, "dbms"),
                                               oracleTempSchema = oracleTempSchema,
                                               cdm_database_schema = cdmDatabaseSchema,
                                               vocabulary_database_schema = vocabularyDatabaseSchema,
                                               
                                               target_database_schema = cohortDatabaseSchema,
                                               target_cohort_table = cohortTable,
                                               target_cohort_id = cohortVarsToCreate$atlasId[i])
      DatabaseConnector::executeSql(connection, sql)
    }
  
  
  }
  
  
  
}
