# Wine 10.17 Custom（Winlator 定制版）

基于 [royel21/wine-10.17-custom](https://github.com/royel21/wine-10.17-custom) 修改，面向 Winlator 的 Wine 10.17 定制编译。

## 相对上游的改动

- 新增 Ubuntu 20.04（glibc 2.31）编译环境，降低运行时 glibc 依赖以兼容 Winlator
- GStreamer 兼容性补丁（GstBufferMapInfo → GstMapInfo），支持 --without-gstreamer 构建
- whp 打包移除 container-pattern，由 app 端自生成

## INTRODUCTION

This is a custom wine for vanilla custom winlator with some patches applied


## QUICK START

From the top-level directory of the Wine source (which contains this file),
run:

Need ubuntu 24.04 (windows subsystem linux)

and run build.sh will install all requirement and compiled wine into a wine-10.17.wcp for installation.

## Thank to for their scripts

To compile and run Wine, you must have one of the following:
- [Frogging-Family/wine-tkg-git](https://github.com/Frogging-Family/wine-tkg-git)

 - [hostei/wine-tkg](https://github.com/hostei33/wine-tkg)

 - [brunodev85/wine-9.2-custom](https://github.com/brunodev85/wine-9.2-custom)

 - [brunodev85/wine-10.10-custom](https://github.com/brunodev85/wine-10.10-custom.git)

 - [longjunyu2/wine-custom](https://github.com/longjunyu2/wine-custom)

 - [AndreRH/wine](https://github.com/AndreRH/wine)

 - [Waim908/wine-termux](https://github.com/Waim908/wine-termux)

 - [FEX-Emu/FEX](https://github.com/FEX-Emu/FEX)

 - [Waim908](https://github.com/Waim908/wine-winlator)