# EasyMultiProfiler Web Application
# Main application file for multi-omics data analysis platform

library(shiny)
library(shinydashboard)
library(shinyjs)
library(DT)
library(ggplot2)
library(RColorBrewer)
library(EasyMultiProfiler)

# Source UI and server modules
source("ui/ui_main.R")
source("server/server_main.R")

# Run the application
shinyApp(ui = ui, server = server)
