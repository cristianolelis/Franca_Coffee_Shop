@echo off
title Painel Cafe Casa Franca
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0painel\servidor.ps1"
if errorlevel 1 pause
