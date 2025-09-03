#!/usr/bin/env pwsh
# ===========================================        if ($initContent -match "'version':\s*\((\d+),\s*(\d+),\s*(\d+)\)") {================================
# DAMTools - Script de Release Automatizado
# ============================================================================
# Este script automatiza el proceso completo de release del addon:
# 1. Construye la documentación (mkdocs build)
# 2. Crea un ZIP limpio del addon 
# 3. Commitea TODOS los cambios pendientes (código + docs + ZIP)
# 4. Crea y pushea el tag de versión
# 5. Publica el GitHub Release con el ZIP adjunto
#
# Uso: .\build_release.ps1 [-Tag] [-Push] [-Clean] [-AutoRelease]

param(
    [switch]$Tag,         # Crear tag git automáticamente
    [switch]$Push,        # Hacer push al repositorio remoto
    [switch]$Clean,       # Limpiar archivos temporales al final
    [switch]$AutoRelease  # Crear release automático en GitHub
)

# Configuración del addon
$ADDON_NAME = "quicksnap"
$ADDON_FOLDER = "quicksnap"  # Nombre de la carpeta en el zip

# Archivos y carpetas a incluir en el release
$INCLUDE_PATHS = @(
    "__init__.py",
    "addon_updater_ops.py",
    "addon_updater.py",
    "LICENSE.md",
    "quicksnap_render.py",
    "quicksnap_shader_gpu_module.py",
    "quicksnap_shader_legacy.py",
    "quicksnap_snapdata.py",
    "quicksnap_utils.py",
    "quicksnap.py",
    "README.md",
    "icons/"
)

# Archivos y carpetas a excluir explícitamente
$EXCLUDE_PATTERNS = @(
    "__pycache__",
    "*.pyc",
    "*.pyo", 
    ".git*",
    "docs/",
    "site/",
    "*.md",
    "*.yml",
    "*.yaml",
    "requirements.txt",
    "build_release.ps1",
    ".cursor/",
    "partnership.mdc",
    "quicksnap-1_0_1_updater/",
    "quicksnap-1_4_7_updater/"
)

Write-Host ">> QuickSnap Release Builder" -ForegroundColor Cyan
Write-Host "=================================" -ForegroundColor Cyan

# Función para extraer versión del __init__.py
function Get-AddonVersion {
    try {
        $initContent = Get-Content "__init__.py" -Raw
        if ($initContent -match '"version":\s*\((\d+),\s*(\d+),\s*(\d+)\)') {
            $major = $matches[1]
            $minor = $matches[2] 
            $patch = $matches[3]
            return "$major.$minor.$patch"
        }
        throw "No se pudo extraer la versión"
    }
    catch {
        Write-Error "ERROR: Error al leer version del __init__.py: $_"
        exit 1
    }
}

# Función para verificar que estamos en un repositorio git limpio
function Test-GitStatus {
    try {
        $status = git status --porcelain 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "WARNING: No se detectó repositorio git"
            return $false
        }
        
        if ($status) {
            Write-Warning "WARNING: Hay cambios sin commitear:"
            git status --short
            $continue = Read-Host "¿Continuar de todas formas? (y/N)"
            return ($continue -eq "y" -or $continue -eq "Y")
        }
        return $true
    }
    catch {
        Write-Warning "WARNING: Error al verificar estado de git: $_"
        return $false
    }
}

# Función para validar que los archivos críticos existen
function Test-CriticalFiles {
    $missing = @()
    foreach ($path in $INCLUDE_PATHS) {
        if (-not (Test-Path $path)) {
            $missing += $path
        }
    }
    
    if ($missing.Count -gt 0) {
        Write-Error "ERROR: Archivos criticos faltantes: $($missing -join ', ')"
        return $false
    }
    return $true
}

# Función para crear el release zip
function New-ReleaseZip {
    param([string]$Version)
    
    $releaseZip = "$ADDON_NAME-v$Version.zip"
    $tempDir = "temp_release"
    $addonDir = Join-Path $tempDir $ADDON_FOLDER
    
    Write-Host ">> Creando release v$Version..." -ForegroundColor Green
    
    try {
        # Limpiar y crear directorio temporal
        if (Test-Path $tempDir) {
            Remove-Item $tempDir -Recurse -Force
        }
        New-Item -ItemType Directory -Path $addonDir -Force | Out-Null
        
        # Copiar archivos incluidos
        foreach ($path in $INCLUDE_PATHS) {
            if (Test-Path $path) {
                $dest = Join-Path $addonDir (Split-Path $path -Leaf)
                if (Test-Path $path -PathType Container) {
                    # Es un directorio
                    Write-Host "  -> Copiando $path/" -ForegroundColor Yellow
                    Copy-Item $path $dest -Recurse -Force
                } else {
                    # Es un archivo
                    Write-Host "  -> Copiando $path" -ForegroundColor Yellow  
                    Copy-Item $path $dest -Force
                }
            }
        }
        
                 # Limpiar archivos excluidos del directorio temporal
         Write-Host "  -> Limpiando archivos de cache y desarrollo..." -ForegroundColor Yellow
         
         # Eliminar carpetas __pycache__ de una vez (más eficiente)
         Get-ChildItem $addonDir -Name "__pycache__" -Recurse -Directory -Force | ForEach-Object {
             $fullPath = Join-Path $addonDir $_
             if (Test-Path $fullPath) {
                 Remove-Item $fullPath -Recurse -Force -ErrorAction SilentlyContinue
                 Write-Host "    -> Eliminada carpeta cache: $_" -ForegroundColor Gray
             }
         }
         
         # Eliminar archivos individuales por patrón
         foreach ($pattern in $EXCLUDE_PATTERNS) {
             if ($pattern -ne "__pycache__" -and $pattern -ne "*.pyc" -and $pattern -ne "*.pyo") {
                 $items = Get-ChildItem $addonDir -Recurse -Force | Where-Object { 
                     $_.Name -like $pattern -or $_.FullName -like "*$pattern*" 
                 }
                 foreach ($item in $items) {
                     if (Test-Path $item.FullName) {
                         Write-Host "    -> Eliminando: $($item.Name)" -ForegroundColor Gray
                         Remove-Item $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
                     }
                 }
             }
         }
        
        # Crear el zip
        Write-Host "  -> Creando $releaseZip..." -ForegroundColor Green
        if (Test-Path $releaseZip) {
            Remove-Item $releaseZip -Force
        }
        
        Compress-Archive -Path (Join-Path $tempDir "*") -DestinationPath $releaseZip -Force
        
        # Mostrar información del zip creado
        $zipSize = (Get-Item $releaseZip).Length / 1KB
        Write-Host "  -> Release creado: $releaseZip ($([math]::Round($zipSize, 2)) KB)" -ForegroundColor Green
        
        # Listar contenido para verificación
        Write-Host "  -> Contenido del release:" -ForegroundColor Cyan
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $releaseZip))
        $zip.Entries | ForEach-Object { 
            Write-Host "   $($_.FullName)" -ForegroundColor Gray
        }
        $zip.Dispose()
        
        return $releaseZip
    }
    catch {
        Write-Error "ERROR: Error al crear release: $_"
        return $null
    }
    finally {
        # Limpiar directorio temporal si se solicita
        if ($Clean -and (Test-Path $tempDir)) {
            Remove-Item $tempDir -Recurse -Force
            Write-Host "  -> Archivos temporales limpiados" -ForegroundColor Gray
        }
    }
}

# Función para construir documentación
function Invoke-MkDocsBuild {
    try {
        Write-Host "  -> Construyendo documentación con mkdocs..." -ForegroundColor Green
        
        mkdocs build --quiet
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  -> Documentación construida exitosamente" -ForegroundColor Green
            return $true
        } else {
            Write-Warning "  -> Error al construir documentación con mkdocs"
            return $false
        }
    }
    catch {
        Write-Warning "  -> Error con mkdocs build: $_"
        return $false
    }
}

# Función para crear tag git
function New-GitTag {
    param([string]$Version)
    
    try {
        $tagName = "v$Version"
        Write-Host "  -> Creando tag $tagName..." -ForegroundColor Green
        
        git tag -a $tagName -m "Release $tagName" 2>$null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  -> Tag $tagName creado" -ForegroundColor Green
            
            if ($Push) {
                Write-Host "  -> Haciendo push del tag..." -ForegroundColor Green
                git push origin $tagName
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  -> Tag enviado al repositorio remoto" -ForegroundColor Green
                    return $true
                } else {
                    Write-Warning "  -> Error al enviar tag al repositorio remoto"
                    return $false
                }
            }
            return $true
        } else {
            Write-Warning "  -> Error al crear tag (puede que ya exista)"
            return $false
        }
    }
    catch {
        Write-Warning "  -> Error con git tag: $_"
        return $false
    }
}

# Función para commit y push de todos los cambios
function Invoke-GitCommitAndPush {
    param([string]$ReleaseZip, [string]$Version)
    
    try {
        Write-Host "  -> Agregando cambios al repositorio..." -ForegroundColor Green
        
        # Agregar todos los cambios (incluyendo el ZIP)
        git add .
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "  -> Error al agregar archivos a git"
            return $false
        }
        
        # Commit con mensaje descriptivo
        $commitMessage = "Release v$Version"
        git commit -m $commitMessage
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  -> Commit creado: $commitMessage" -ForegroundColor Green
            
            if ($Push) {
                Write-Host "  -> Haciendo push de commits..." -ForegroundColor Green
                git push
                if ($LASTEXITCODE -eq 0) {
                    Write-Host "  -> Commits enviados al repositorio remoto" -ForegroundColor Green
                    return $true
                } else {
                    Write-Warning "  -> Error al enviar commits al repositorio remoto"
                    return $false
                }
            }
            return $true
        } else {
            Write-Host "  -> Sin cambios para commitear (ZIP ya existe en repo)" -ForegroundColor Yellow
            return $true
        }
    }
    catch {
        Write-Warning "  -> Error en commit/push: $_"
        return $false
    }
}

# Función para crear GitHub Release
function New-GitHubRelease {
    param([string]$Version, [string]$ReleaseZip)
    
    try {
        $tagName = "v$Version"
        Write-Host "  -> Creando GitHub Release $tagName..." -ForegroundColor Green
        
        # Verificar que GitHub CLI está disponible
        $ghVersion = gh --version 2>$null
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "  -> GitHub CLI no está instalado o configurado"
            return $false
        }
        
        # Crear el release con el ZIP adjunto
        $releaseTitle = "DAMTools v$Version"
        $releaseNotes = @"
## QuickSnap v$Version

### Release Notes
- Blender addon for quickly snapping objects/vertices/curve points
- Duplicate objects and snap functionality
- Interactive vertex/edge/face snapping

### Installation
1. Download the \`$ReleaseZip\` file below
2. In Blender: Edit > Preferences > Add-ons > Install
3. Select the downloaded ZIP file
4. Enable QuickSnap addon

### What's Included
- All operators and snapping functionality
- Icon assets
- Complete addon package

For more information, visit our [GitHub repository](https://github.com/SynrgStudio/quicksnap).
"@
        
        gh release create $tagName $ReleaseZip --title $releaseTitle --notes $releaseNotes
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  -> GitHub Release creado exitosamente!" -ForegroundColor Green
            Write-Host "  -> URL: https://github.com/$(git config --get remote.origin.url | ForEach-Object { $_ -replace '.*github\.com[:/]', '' } | ForEach-Object { $_ -replace '\.git$', '' })/releases/tag/$tagName" -ForegroundColor Cyan
            return $true
        } else {
            Write-Warning "  -> Error al crear GitHub Release"
            return $false
        }
    }
    catch {
        Write-Warning "  -> Error al crear GitHub Release: $_"
        return $false
    }
}

# ============================================================================
# MAIN SCRIPT
# ============================================================================

# Verificar que estamos en el directorio correcto
if (-not (Test-Path "__init__.py")) {
    Write-Error "ERROR: No se encontró __init__.py. Ejecuta este script desde la raíz del proyecto."
    exit 1
}

# Verificar archivos críticos
if (-not (Test-CriticalFiles)) {
    exit 1
}

# Obtener versión
$version = Get-AddonVersion
Write-Host "  -> Versión detectada: v$version" -ForegroundColor Cyan

# AutoRelease activa automáticamente Tag y Push
if ($AutoRelease) {
    $Tag = $true
    $Push = $true
    Write-Host "  -> AutoRelease activado (Tag y Push automáticos)" -ForegroundColor Cyan
}

# Verificar estado git (solo si NO es AutoRelease)
if ($Tag -and -not $AutoRelease -and -not (Test-GitStatus)) {
    Write-Host "ERROR: Estado de git no es válido para crear tag" -ForegroundColor Red
    exit 1
}

# Autorelease completo
if ($AutoRelease) {
    Write-Host "`n>> Iniciando AutoRelease completo..." -ForegroundColor Cyan
    
    # 1. Construir documentación (comentado - no hay docs en QuickSnap)
    # $docsSuccess = Invoke-MkDocsBuild
    # if (-not $docsSuccess) {
    #     Write-Warning "Fallo en mkdocs build, continuando..."
    # }
    
    # 2. Crear release ZIP
    $releaseZip = New-ReleaseZip -Version $version
    if (-not $releaseZip) {
        Write-Error "ERROR: No se pudo crear ZIP de release."
        exit 1
    }
    
    # 3. Commit y push de todos los cambios (incluyendo ZIP)
    $commitSuccess = Invoke-GitCommitAndPush -ReleaseZip $releaseZip -Version $version
    if (-not $commitSuccess) {
        Write-Warning "Fallo en commit/push, continuando con tag..."
    }
    
    # 4. Crear y push tag
    $tagSuccess = New-GitTag -Version $version
    if (-not $tagSuccess) {
        Write-Error "ERROR: No se pudo crear/push tag. Abortando AutoRelease."
        exit 1
    }
    
    # 5. Crear GitHub Release
    $releaseSuccess = New-GitHubRelease -Version $version -ReleaseZip $releaseZip
    if (-not $releaseSuccess) {
        Write-Error "ERROR: No se pudo crear GitHub Release."
        exit 1
    }
}
else {
    # Crear release ZIP para otros modos
    $releaseZip = New-ReleaseZip -Version $version
    if (-not $releaseZip) {
        exit 1
    }
    
    # Crear tag solamente si se solicita (y no es AutoRelease)
    if ($Tag) {
        New-GitTag -Version $version
    }
}

Write-Host "`n  -> Release completado exitosamente!" -ForegroundColor Green
Write-Host "   Archivo: $releaseZip" -ForegroundColor White
Write-Host "   Versión: v$version" -ForegroundColor White

if ($AutoRelease) {
    Write-Host "   Tag: v$version (creado y pusheado)" -ForegroundColor Green
    Write-Host "   GitHub Release: Creado automaticamente" -ForegroundColor Green
    Write-Host "   Estado: LISTO PARA DISTRIBUCION" -ForegroundColor Green
    
    Write-Host "`n  -> AutoRelease completado!" -ForegroundColor Cyan
    Write-Host "   1. Addon empaquetado en ZIP" -ForegroundColor Gray
    Write-Host "   2. Todos los cambios commiteados al repositorio (codigo + ZIP)" -ForegroundColor Gray
    Write-Host "   3. Tag v$version creado y pusheado" -ForegroundColor Gray  
    Write-Host "   4. GitHub Release publicado con ZIP adjunto" -ForegroundColor Gray
    Write-Host "   5. Addon listo para descarga publica" -ForegroundColor Gray
}
elseif ($Tag) {
    Write-Host "   Tag: v$version" -ForegroundColor White
    
    Write-Host "`n  -> Proximos pasos:" -ForegroundColor Yellow
    Write-Host "   1. Probar el addon instalando $releaseZip en Blender" -ForegroundColor Gray
    Write-Host "   2. Subir a GitHub Releases manualmente" -ForegroundColor Gray
}
else {
    Write-Host "`n  -> Proximos pasos:" -ForegroundColor Yellow
    Write-Host "   1. Probar el addon instalando $releaseZip en Blender" -ForegroundColor Gray
    Write-Host "   2. Crear release completo con: .\build_release.ps1 -AutoRelease" -ForegroundColor Gray
    Write-Host "   3. O solo tag con: .\build_release.ps1 -Tag" -ForegroundColor Gray
} 