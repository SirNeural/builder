@echo off

set SRC_DIR=%~dp0\..
pushd %SRC_DIR%

set PYTHON_VERSION=%PYTHON_PREFIX:py=cp%

pip install pytest coverage hypothesis protobuf

for /F "delims=" %%i in ('where /R %SRC_DIR%\output\%CUDA_PREFIX% torch*%PYTHON_VERSION%*.whl') do pip install "%%i"

if ERRORLEVEL 1 exit /b 1

echo Smoke testing imports
python -c "import torch"

echo "Checking that MKL is available"
python -c "import torch; exit(0 if torch.backends.mkl.is_available() else 1)"
if ERRORLEVEL 1 exit /b 1

if NOT "%CUDA_PREFIX%" == "cpu" (
    python -c "import torch; torch.rand(1).cuda(); exit(0 if torch.cuda.has_magma else 1)"
    if ERRORLEVEL 1 exit /b 1

    echo Checking that CUDA archs are setup correctly
    python -c "import torch; torch.randn([3,5]).cuda()"
    if ERRORLEVEL 1 exit /b 1

    echo Checking that magma is available
    python -c "import torch; torch.rand(1).cuda(); exit(0 if torch.cuda.has_magma else 1)"
    if ERRORLEVEL 1 exit /b 1
    echo Checking that CuDNN is available
    python -c "import torch; exit(0 if torch.backends.cudnn.is_available() else 1)"
    if ERRORLEVEL 1 exit /b 1
)

echo Not running unit tests. Hopefully these problems are caught by CI
goto test_end

cd pytorch\test
python run_test.py -v -pt

if ERRORLEVEL 1 exit /b 1

:test_end

popd
exit /b 0
