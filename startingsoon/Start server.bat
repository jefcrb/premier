@echo off
title Starting Soon overlay server
cd /d "%~dp0"
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0server.ps1"
