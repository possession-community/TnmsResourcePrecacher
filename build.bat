@echo off
setlocal enabledelayedexpansion

REM Parse command line arguments
set PLATFORM=win-x64
set PLATFORM_NAME=Windows
if /I "%1"=="linux" (
    set PLATFORM=linux-x64
    set PLATFORM_NAME=Linux
) else if /I "%1"=="windows" (
    set PLATFORM=win-x64
    set PLATFORM_NAME=Windows
) else if not "%1"=="" (
    echo Invalid platform: %1
    echo Usage: build.bat [windows^|linux]
    echo   windows - Build for Windows ^(default^)
    echo   linux   - Build for Linux
    exit /b 1
)


REM Define custom directories to copy, This is only effective when %MOD_SHARP_DIR% is set
set OVERRIDE_CUSTOMS=0
if /I "%2"=="--override-custom-files" (
    set OVERRIDE_CUSTOMS=1
)

title Building TNMS Projects for %PLATFORM_NAME%
rd ".build/gamedata" /S /Q
rd ".build/modules" /S /Q
rd ".build/shared" /S /Q
cls

echo Building TNMS Projects for %PLATFORM_NAME% (%PLATFORM%)
echo:

REM Define projects to build (add/remove projects as needed)
set PROJECTS=TnmsResourcePrecacher

REM Define shared projects in dependency order (base projects first)
set SHARED_PROJECTS_PHASE1=
set SHARED_PROJECTS_PHASE2=

REM Define build only shared projects (these projects will not be copied to shared directory)
set BUILD_ONLY_SHARED_PROJECTS=

REM Define DLLs to remove (provided by ModSharp)
set DLLS_TO_REMOVE=Google.Protobuf.dll McMaster.NETCore.Plugins.dll Microsoft.Extensions.Configuration.dll Microsoft.Extensions.Configuration.Abstractions.dll Microsoft.Extensions.Configuration.Binder.dll Microsoft.Extensions.Configuration.FileExtensions.dll Microsoft.Extensions.Configuration.Json.dll Microsoft.Extensions.DependencyInjection.dll Microsoft.Extensions.DependencyInjection.Abstractions.dll Microsoft.Extensions.Diagnostics.dll Microsoft.Extensions.Diagnostics.Abstractions.dll Microsoft.Extensions.FileProviders.Abstractions.dll Microsoft.Extensions.FileProviders.Physical.dll Microsoft.Extensions.FileSystemGlobbing.dll Microsoft.Extensions.Http.dll Microsoft.Extensions.Logging.dll Microsoft.Extensions.Logging.Abstractions.dll Microsoft.Extensions.Logging.Configuration.dll Microsoft.Extensions.Logging.Console.dll Microsoft.Extensions.Options.dll Microsoft.Extensions.Options.ConfigurationExtensions.dll Microsoft.Extensions.Primitives.dll Serilog.dll Serilog.Extensions.Logging.dll Serilog.Sinks.Console.dll Serilog.Sinks.File.dll Serilog.Sinks.Async.dll Serilog.Expressions.dll System.Text.Json e_sqlite3.dll

REM Define Shared DLLs to remove (these are provided by shared directory)
set SHARED_DLLS_TO_REMOVE=TnmsPluginFoundation.dll Wuling.Abstract.dll

REM Define custom directories to copy from main project to build output (these are only copied when %MOD_SHARP_DIR% is set)
set CUSTOM_DIRS=maps

echo Building shared projects (Phase 1 - Base projects)...
for %%P in (%SHARED_PROJECTS_PHASE1%) do (
    if exist "%%P\%%P.csproj" (
        echo Building shared project: %%P
        dotnet publish %%P/%%P.csproj -f net10.0 -r %PLATFORM% --disable-build-servers --no-self-contained -c Release -p:DebugType=None -p:DebugSymbols=false --output ".build/shared/%%P"
        if !ERRORLEVEL! neq 0 (
            echo Error publishing %%P
            exit /b 1
        )
        
        echo Removing DLLs that already present in ModSharp from %%P...
        for %%D in (%DLLS_TO_REMOVE%) do (
            if exist ".build\shared\%%P\%%D" (
                del ".build\shared\%%P\%%D" /Q
            )
        )
        echo:
    )
)

echo Building shared projects (Phase 2 - Dependent projects)...
for %%P in (%SHARED_PROJECTS_PHASE2%) do (
    if exist "%%P\%%P.csproj" (
        echo Building shared project: %%P
        dotnet publish %%P/%%P.csproj -f net10.0 -r %PLATFORM% --disable-build-servers --no-self-contained -c Release -p:DebugType=None -p:DebugSymbols=false --output ".build/shared/%%P"
        if !ERRORLEVEL! neq 0 (
            echo Error publishing %%P
            exit /b 1
        )
        
        echo Removing DLLs that already present in ModSharp from %%P...
        for %%D in (%DLLS_TO_REMOVE%) do (
            if exist ".build\shared\%%P\%%D" (
                del ".build\shared\%%P\%%D" /Q
            )
        )
        echo:
    )
)

echo Building build-only shared projects...
for %%P in (%BUILD_ONLY_SHARED_PROJECTS%) do (
    if exist "%%P\%%P.csproj" (
        echo Building build-only shared project: %%P
        dotnet publish %%P/%%P.csproj -f net10.0 -r %PLATFORM% --disable-build-servers --no-self-contained -c Release -p:DebugType=None -p:DebugSymbols=false --output ".build/shared/%%P"
        if !ERRORLEVEL! neq 0 (
            echo Error publishing %%P
            exit /b 1
        )
        
        echo Removing DLLs that already present in ModSharp from %%P...
        for %%D in (%DLLS_TO_REMOVE%) do (
            if exist ".build\shared\%%P\%%D" (
                del ".build\shared\%%P\%%D" /Q
            )
        )
        echo:
    )
)

echo:
echo Building main projects...
for %%P in (%PROJECTS%) do (
    if exist "%%P\%%P.csproj" (
        echo Building project: %%P
        dotnet publish %%P/%%P.csproj -f net10.0 -r %PLATFORM% --disable-build-servers --no-self-contained -c Release -p:DebugType=None -p:DebugSymbols=false --output ".build/modules/%%P"
        if !ERRORLEVEL! neq 0 (
            echo Error publishing %%P
            exit /b 1
        )        
        
        echo Removing DLLs that already present in ModSharp from %%P...
        for %%D in (%DLLS_TO_REMOVE%) do (
            if exist ".build\modules\%%P\%%D" (
                del ".build\modules\%%P\%%D" /Q
            )
        )
        
        REM remove shared TNMSPluginFoundation DLLs
        echo Removing Shared DLLs...
        for %%S in (%SHARED_DLLS_TO_REMOVE%) do (
            if exist ".build\modules\%%P\%%S" (
                echo Removing %%S from %%P
                del ".build\modules\%%P\%%S" /Q
            )
        )        
        
        REM Move all DLLs except the main plugin DLL to dependencies directory
        set MAIN_DLL=%%P.dll
        set MODULE_DIR=.build\modules\%%P
        set DEP_DIR=!MODULE_DIR!\
        set HAS_DEPENDENCIES=0
        
        REM Check if there are any dependency DLLs to move
        for %%F in (!MODULE_DIR!\*.dll) do (
            if /I not "%%~nxF"=="!MAIN_DLL!" (
                set HAS_DEPENDENCIES=1
            )
        )
        
        REM Only create dependencies directory and move files if dependencies exist
        if !HAS_DEPENDENCIES! EQU 1 (
            if not exist "!DEP_DIR!" (
                mkdir "!DEP_DIR!"
            )
            
            for %%F in (!MODULE_DIR!\*.dll) do (
                if /I not "%%~nxF"=="!MAIN_DLL!" (
                    move "%%F" "!DEP_DIR!\"
                )
            )
        )
        
        echo Renaming appsettings.json for %%P...
        if exist ".build\modules\%%P\appsettings.json" move ".build\modules\%%P\appsettings.json" ".build\modules\%%P\appsettings.example.json"
        
        REM Copy custom files that defined
        for %%C in (!CUSTOM_DIRS!) do (
            if exist "%%C\" (
                echo Copying %%C files for %%P...
                xcopy "%%C\*" ".build\modules\%%P\%%C\" /E /I /Y
            )
        )
        
        REM Copy global.toml file
        if exist "global.toml" (
            echo Copying global.toml for %%P...
            xcopy "global.toml" ".build\modules\%%P\" /I /Y
        )
        
        
        echo:
    ) else (
        echo Warning: %%P.csproj not found, skipping...
    )
)

echo Copying GameData...
if exist "gamedata\" xcopy "gamedata\*" ".build/gamedata/" /E /I /Y

echo:
echo Build and copy completed for all projects.

REM Copy to ModSharp directory if MOD_SHARP_DIR is set
if "%MOD_SHARP_DIR%"=="" (
    echo MOD_SHARP_DIR environment variable is not set. Skipping ModSharp copy.
    echo To enable ModSharp copy, set MOD_SHARP_DIR environment variable to your ModSharp installation path.
) else (
    echo:
    echo Copying to ModSharp directory: %MOD_SHARP_DIR%
    
    echo Copying shared projects to ModSharp...
    for %%P in (%SHARED_PROJECTS_PHASE1%) do (
        if exist ".build\shared\%%P\" (
            echo Copying %%P to ModSharp shared directory...
            xcopy ".build\shared\%%P\*" "%MOD_SHARP_DIR%\shared\%%P\" /E /I /Y
        )
    )
    for %%P in (%SHARED_PROJECTS_PHASE2%) do (
        if exist ".build\shared\%%P\" (
            echo Copying %%P to ModSharp shared directory...
            xcopy ".build\shared\%%P\*" "%MOD_SHARP_DIR%\shared\%%P\" /E /I /Y
        )
    )
    
    echo Copying main projects to ModSharp...
    for %%P in (%PROJECTS%) do (
        if exist ".build\modules\%%P\" (
        
            if %OVERRIDE_CUSTOMS% EQU 0 (
                echo Removing existing custom directories for %%P in ModSharp...
                for %%C in (%CUSTOM_DIRS%) do (
                    if exist ".build\modules\%%P\%%C\" (
                        rd ".build\modules\%%P\%%C\" /S /Q
                    )
                    
                    if exist ".build\modules\%%P\global.toml" (
                        del ".build\modules\%%P\global.toml" /Q
                    )
                )
            )
            
            echo Copying %%P to ModSharp modules directory...
            xcopy ".build\modules\%%P\*" "%MOD_SHARP_DIR%\modules\%%P\" /E /I /Y
        )
    )
    
    echo Copying GameData to ModSharp...
    if exist ".build\gamedata\" xcopy ".build\gamedata\*" "%MOD_SHARP_DIR%\gamedata\" /E /I /Y
    
    echo:
    echo Successfully copied all projects to ModSharp directory.
)

echo: