# 崩溃分析与最终修复方案

## 崩溃特征

```
Fatal signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x0
rip 0000000000000000  <unknown>
```
这是一个极其经典的 **Null Pointer Dereference (尝试执行 0x0 地址)** 错误。
发生时机：**紧接着** `Initializing Clash Core (FlClash Native)...` 日志之后，但在 `Init Sent.` 之前。

这意味着：**`INSTANCE.invokeAction` 调用瞬间就崩了**，甚至没进到 Go 运行时。JNA 尝试解析库或调用函数时直接跳到了空地址。

## 根本原因

经过仔细分析，我认为问题出在 **JNA 加载机制** 上，而不是 Go 库本身。
在 `ClashVpnService.kt` 中：
```kotlin
val INSTANCE: ClashLibrary by lazy {
    Native.load("clash", ClashLibrary::class.java)
}
```
`Native.load("clash", ...)` 会尝试加载 `libclash.so`。
但是，我们**自定义的** `invokeAction` 函数签名在 Go `c-shared` 模式导出时，并不是标准的 C 调用约定 (cdecl) 或者 JNA 匹配出现了细微偏差。

此外，更致命的是，**`libclash.so` 并没有被正确加载**。
`D/nativeloader... Load ... libjnidispatch.so ... ok` 显示 JNA 自己的库加载了。
**但没有看到 `libclash.so` 加载成功的日志**。

通常 `Native.load` 失败会抛异常，但如果是在 JNA 内部映射函数指针时出错（比如符号没找到，或者符号名被 mangle 了），可能会导致这种野指针跳转崩溃。

## 验证：符号名问题

Go `c-shared` 导出的符号就是函数名本身。
但是 JNA 默认可能会去寻找 `invokeAction`。
请注意，我们在 Go 中导出了 `Start` 和 `Stop` (为了配合最开始的方案)，**但是后来我们改用了 FlClash 的 `invokeAction` 接口**。
**关键问题来了：**
我们的 `FINAL_UBUNTU_BUILD_SCRIPT.sh` 中，虽然复制了 `lib.go`，但那个 `lib.go` 里导出的是：
```go
//export Start
func Start(...) ...
//export Stop
func Stop() ...
```
**但是！！**
在 `ClashVpnService.kt` 中，我们定义的接口是：
```kotlin
interface ClashLibrary : Library {
    fun invokeAction(...)
    fun startTUN(...)
    fun stopTun()
}
```
**不匹配！完全不匹配！**
我们编译的 `.so` 里只有 `Start` 和 `Stop`。
但我们 Kotlin 代码里调用的是 `invokeAction`。
JNA 尝试查找 `invokeAction` 符号，找不到，或者找到个空指针，一调用就炸了 (0x0)。

## 修复方案

**我们必须让 Kotlin 代码调用 `.so` 里真实存在的函数。**

既然我们刚刚编译的 `.so` 是基于我写的那个 `lib.go` (只包含 `Start` 和 `Stop`)，那我们就应该**回退到使用 `Start` 和 `Stop` 的 Kotlin 代码**，而不是去模仿 FlClash 的复杂 `invokeAction` 接口。

**行动**：
修改 `ClashVpnService.kt`，改回调用 `Start` 和 `Stop`。这将最简单、最稳妥。

我们之前改用 FlClash 接口是因为以为您用了 FlClash 原版编译的库。但既然我们实际上用了**自定义脚本编译的库**，那我们就拥有了定义接口的权利。

**自定义库接口回顾**:
```go
//export Start
func Start(homeDir *C.char, configContent *C.char) *C.char
```

我们将修改 Kotlin 来匹配这个接口。
