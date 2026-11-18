# 📘 คู่มือฉบับสมบูรณ์ (Exhaustive Reference): Potassium API Documentation
> **อ้างอิงอย่างเป็นทางการ:** [Potassium Docs](https://docs.potassium.pro/api-reference/introduction)  
> **มาตรฐาน:** UNC (Unified Naming Convention) Standard + Potassium Extensions  
> **ภาษาที่ใช้:** Luau (Roblox Lua)

---

## 📑 สารบัญหมวดหมู่ API ทั้งหมด (22 หมวดหมู่)

1. [Actor Library (Parallel Luau)](#1-actor-library-parallel-luau)
2. [Cache Library](#2-cache-library)
3. [Closure Library & Hooking](#3-closure-library--hooking)
4. [Console Library](#4-console-library)
5. [Crypt Library (Cryptography)](#5-crypt-library-cryptography)
6. [Debug Library](#6-debug-library)
7. [Drawing Library & 2D Objects](#7-drawing-library--2d-objects)
8. [DrawingImmediate Library](#8-drawingimmediate-library)
9. [Environment Library](#9-environment-library)
10. [FileSystem Library](#10-filesystem-library)
11. [Input Library (Input Simulation)](#11-input-library-input-simulation)
12. [Instance Library](#12-instance-library)
13. [Oth Library (Off-Thread Hooking)](#13-oth-library-off-thread-hooking)
14. [Metatable Library](#14-metatable-library)
15. [Miscellaneous Library](#15-miscellaneous-library)
16. [PsmSignal Library](#16-psmsignal-library)
17. [RakNet Library (Network Packet Control)](#17-raknet-library-network-packet-control)
18. [Reflection Library (Hidden Properties & Internal Data)](#18-reflection-library-hidden-properties--internal-data)
19. [Regex Library](#19-regex-library)
20. [Script Library](#20-script-library)
21. [Signal Library](#21-signal-library)
22. [WebSocket Library](#22-websocket-library)
23. [สูตรการนำไป Mod แมพ Mount RNG (Practical Modding Recipes)](#23-สูตรการนำไป-mod-แมพ-mount-rng)

---

## 1. Actor Library (Parallel Luau)

| ฟังก์ชัน / เมธอด | คำอธิบายรายละเอียดและพารามิเตอร์ |
| :--- | :--- |
| `create_comm_channel()` | คืนค่า Channel Identifier (`string`) และ `BindableEvent` สำหรับใช้รับส่งข้อมูลแบบ One-way ระหว่าง Actors |
| `get_comm_channel(id)` | คืนค่า `BindableEvent` จาก Channel ID ที่เคยสร้างไว้ด้วย `create_comm_channel` |
| `getactors()` | คืนค่าตาราง (`table`) ของ `Actor` ทั้งหมดในเกมที่ไม่ถูกลบ (เกมบางเกมลบ Actor ขณะทำงานอยู่) |
| `getactorthreads()` | คืนค่าตาราง (`table`) ของทุก `thread` ที่เชื่อมต่ออยู่กับทุก Actor ในระบบ |
| `getdeletedactors()` | คืนค่าตารางของ `Actor` ทั้งหมดที่ถูกลบออกไปแล้ว |
| `is_parallel()` | คืนค่า `boolean` บอกว่าโค้ดปัจจุบันกำลังทำงานในสภาวะ Parallel (ความขนาน) อยู่หรือไม่ |
| `run_on_actor(actor, code)` | รันโค้ดสคริปต์ (`code: string`) บน Actor ที่กำหนด |
| `run_on_thread(thread, code)` | รันโค้ดสคริปต์ (`code: string`) บน Thread เฉพาะของ Actor |

---

## 2. Cache Library

| ฟังก์ชัน / เมธอด | คำอธิบายรายละเอียดและพารามิเตอร์ |
| :--- | :--- |
| `cloneref(instance)` | โคลน Reference ของ Roblox Instance เพื่อให้ชี้ไปยังวัตถุเดิมแต่เปลี่ยน Memory Pointer เพื่อหลบการตรวจจับ |
| `compareinstances(inst1, inst2)` | คืนค่า `boolean` เช็คว่า Reference 2 ตัวใน Cache ชี้ไปยัง Instance เดียวกันหรือไม่ |
| `cache.invalidate(instance)` | ลบ Instance ออกจาก internal reference cache ของ Executor |
| `cache.iscached(instance)` | คืนค่า `boolean` เช็คว่า Instance นั้นมีอยู่ใน reference cache หรือไม่ |
| `cache.replace(oldInst, newInst)` | แทนที่ `oldInst` ด้วย `newInst` ภายใน internal cache ของระบบ |

---

## 3. Closure Library & Hooking

| ฟังก์ชัน / เมธอด | คำอธิบายรายละเอียดและพารามิเตอร์ |
| :--- | :--- |
| `hookfunction(oldFunc, newFunc)` | Hook ฟังก์ชัน Lua หรือ C และคืนค่า Original Function สำหรับเรียกใช้ภายหลัง |
| `restorefunction(func)` | คืนค่าฟังก์ชันที่เคยถูก Hook ด้วย `hookfunction` กลับไปเป็นโค้ดดั้งเดิม |
| `isfunctionhooked(func)` | คืนค่า `boolean` เช็คว่าฟังก์ชันนั้นกำลังถูก Hook อยู่หรือไม่ |
| `newcclosure(func)` | สร้าง C Closure ใหม่จาก Lua function เพื่อให้เกมเข้าใจว่าเป็น C function (หลบการเช็ค `islclosure`) |
| `newlclosure(func)` | สร้าง Lua Closure ใหม่จากฟังก์ชันที่กำหนด |
| `iscclosure(func)` | คืนค่า `boolean` เช็คว่าฟังก์ชันเป็น C Closure หรือไม่ |
| `islclosure(func)` | คืนค่า `boolean` เช็คว่าฟังก์ชันเป็น Lua Closure หรือไม่ |
| `isexecutorclosure(func)` | คืนค่า `boolean` เช็คว่าฟังก์ชันนั้นสร้างขึ้นโดย Potassium หรือไม่ |
| `isnewcclosure(func)` | คืนค่า `boolean` เช็คว่าฟังก์ชันถูกสร้างมาจาก `newcclosure` หรือไม่ |
| `isourthread(thread)` | คืนค่า `boolean` เช็คว่า Thread นั้นเป็น Thread ของ Potassium หรือไม่ |
| `getfunctionhash(func)` | คืนค่าข้อความ Hash ของฟังก์ชัน Lua สำหรับตรวจสอบการดัดแปลงโค้ด |
| `loadstring(code, chunkName?)` | คอมไพล์ String ให้กลายเป็น Lua Chunk (ฟังก์ชัน) คืนค่า `function, err` |
| `setstackhidden(func, hidden)` | ตั้งค่าซ่อนฟังก์ชันจากการตรวจจับผ่าน Call-stack (Call-stack based detections) |

---

## 4. Console Library

| ฟังก์ชัน / เมธอด | คำอธิบายรายละเอียดและพารามิเตอร์ |
| :--- | :--- |
| `rconsolecreate()` | สร้างหน้าต่าง External Console ภายนอก |
| `rconsoledestroy()` | ทำลายหน้าต่าง External Console และล้างความทรงจำทั้งหมด |
| `rconsoleclear()` | ล้างข้อความทั้งหมดใน Console |
| `rconsoleprint(text)` | พิมพ์ข้อความสีขาวออกทาง Console |
| `rconsoleinfo(text)` | พิมพ์ข้อความสีน้ำเงินเข้ม (Info) |
| `rconsolewarn(text)` | พิมพ์ข้อความสีเหลือง (Warning) |
| `rconsoleerror(text)` | พิมพ์ข้อความสีแดง (Error) |
| `rconsolesettitle(title)` | ตั้งชื่อหัวข้อ (Title Bar) ของหน้าต่าง Console |
| `rconsoleinput()` | สั่งให้ Thread หยุดรอรับข้อความ Input ที่ผู้ใช้พิมพ์ใส่ใน Console |

---

## 5. Crypt Library (Cryptography)

| ฟังก์ชัน / เมธอด | คำอธิบายรายละเอียดและพารามิเตอร์ |
| :--- | :--- |
| `crypt.base64encode(data)` | แปลงข้อความ/ข้อมูลเป็นรูปแบบ Base64 Encoding |
| `crypt.base64decode(encoded)` | ถอดรหัสข้อความจาก Base64 กลับเป็นข้อมูลปกติ |
| `crypt.encrypt(data, key, iv?, mode?)` | เข้ารหัสข้อมูลด้วย AES คืนค่า `encryptedData, iv` |
| `crypt.decrypt(data, key, iv, mode?)` | ถอดรหัสข้อมูล AES ที่เข้ารหัสไว้ คืนค่า `decryptedData` |
| `crypt.generatekey()` | สุ่มสร้าง Encryption Key ความยาวมาตรฐาน |
| `crypt.generatebytes(length)` | สุ่มสร้าง Byte Data ตามความยาวที่กำหนด (คืนค่าเป็น Base64) |
| `crypt.random(length)` | สุ่มสร้าง Byte Data (คืนค่าเป็น Raw string ไม่ผ่าน Base64) |
| `crypt.hash(data, algorithm)` | สร้าง Hash จากข้อมูลตามอัลกอริทึมที่เลือก (เช่น `"sha256"`, `"md5"`) |
| `crypt.hmac(data, key, algorithm)` | สร้าง HMAC (Hash-based Message Authentication Code) |
| `crypt.lz4compress(data)` | บีบอัดข้อมูลด้วยอัลกอริทึม LZ4 Compression |
| `crypt.lz4decompress(data)` | คลายการบีบอัดข้อมูล LZ4 |

---

## 6. Debug Library

| ฟังก์ชัน / เมธอด | คำอธิบายรายละเอียดและพารามิเตอร์ |
| :--- | :--- |
| `debug.getinfo(func/level)` | คืนค่า `table` ข้อมูลรายละเอียดฟังก์ชัน (`source`, `short_src`, `linedefined`, `what`, `nups`, `func`) |
| `debug.getcallstack()` | คืนค่า `table` รายการ Callstack ทั้งหมดในขณะนั้น |
| `debug.getconstants(func)` | คืนค่าตาราง Constants ทั้งหมดของฟังก์ชัน |
| `debug.getconstant(func, index)` | คืนค่า Constant ณ ตำแหน่ง Index ที่กำหนด |
| `debug.setconstant(func, index, value)` | แก้ไขค่า Constant ณ ตำแหน่ง Index ที่กำหนด |
| `debug.getupvalues(func)` | คืนค่าตาราง Upvalues ทั้งหมดของฟังก์ชัน |
| `debug.getupvalue(func, index)` | คืนค่า Upvalue ณ ตำแหน่ง Index |
| `debug.setupvalue(func, index, value)` | แก้ไขค่า Upvalue ณ ตำแหน่ง Index |
| `debug.getstack(level)` | คืนค่าตาราง Objects ทั้งหมดที่อยู่บน Stack ณ Level ที่กำหนด |
| `debug.setstack(level, index, value)` | เปลี่ยนแปลง Object บน Stack ณ Level และ Index |
| `debug.getprotos(func)` | คืนค่าตาราง Protos ทั้งหมดที่อยู่ในฟังก์ชัน |
| `debug.getproto(func, index, active?)` | คืนค่า Proto ณ Index ที่กำหนด |
| `debug.getregistry()` | คืนค่า Global Lua Registry Table |
| `debug.getsafeenv(obj)` | คืนค่าสถานะ Safe Environment Flag |
| `debug.setsafeenv(obj, enabled)` | ตั้งค่า Safe Environment Flag |
| `debug.isvalidlevel(level)` | คืนค่า `boolean` เช็คว่า Stack level ที่ระบุมีจริงหรือไม่ |
| `debug.setinfo(func, infoTable)` | ตั้งค่า Debug Info ของฟังก์ชัน |
| `debug.setname(func, name)` | เปลี่ยนชื่อของฟังก์ชันในระบบ Debug |

---

## 7. Drawing Library & 2D Objects

### ฟังก์ชันทั่วไป:
* `Drawing.new(objectType)` : สร้างวัตถุวาด 2D ใหม่ (ประเภท: `"Line"`, `"Text"`, `"Image"`, `"Circle"`, `"Square"`, `"Triangle"`, `"Quad"`, `"Shader"`)
* `cleardrawcache()` : ลบและทำลาย Drawing Objects ทั้งหมดออกจากความจำ
* `isrenderobj(obj)` : เช็คว่าวัตถุนั้นเป็น Drawing Object หรือไม่
* `getrenderproperty(obj, property)` : อ่านค่าความสามารถของ Drawing Object
* `setrenderproperty(obj, property, value)` : ตั้งค่าความสามารถของ Drawing Object

### วัตถุวาด และ Properties สำคัญ:
1. **Base Object (วัตถุพื้นฐาน):** `Visible` (`bool`), `ZIndex` (`number`), `Transparency` (`number`), `Color` (`Color3`), `Remove()`
2. **Line:** `From` (`Vector2`), `To` (`Vector2`), `Thickness` (`number`)
3. **Text:** `Text` (`string`), `Size` (`number`), `Position` (`Vector2`), `Center` (`bool`), `Outline` (`bool`), `OutlineColor` (`Color3`), `Font` (`number`)
4. **Image:** `Data` (`string`), `Position` (`Vector2`), `Size` (`Vector2`), `Rounding` (`number`)
5. **Circle:** `Position` (`Vector2`), `Radius` (`number`), `Filled` (`bool`), `Thickness` (`number`), `NumSides` (`number`)
6. **Square:** `Position` (`Vector2`), `Size` (`Vector2`), `Filled` (`bool`), `Thickness` (`number`)
7. **Triangle / Quad:** `PointA`, `PointB`, `PointC`, (`PointD`), `Filled`, `Thickness`
8. **Shader:** ใช้วาด HLSL Custom Shaders บนหน้าจอ

---

## 8. DrawingImmediate Library

* `DrawingImmediate.GetPaint(zIndex)` : คืนค่า Custom Event ที่จะส่งสัญญาณถูกเรียกทุก Render Step ตามลำดับ `zIndex`
* **ข้อจำกัด:** APIs ในกลุ่ม `DrawingImmediate.*` สามารถเรียกใช้งานได้เฉพาะภายใน Event ของ `GetPaint` เท่านั้น

---

## 9. Environment Library

| ฟังก์ชัน / เมธอด | คำอธิบายรายละเอียดและพารามิเตอร์ |
| :--- | :--- |
| `getgenv()` | คืนค่า Global Environment Table ของ Potassium (แชร์ข้อมูลข้ามสคริปต์ที่รันโดย Potassium ได้) |
| `getrenv()` | คืนค่า Roblox Global Environment Table ดั้งเดิมของเกม |
| `getsenv(script)` | คืนค่า Environment Table ของสคริปต์เฉพาะตัว (`Script`, `LocalScript`, `ModuleScript`) |
| `gettenv(thread)` | คืนค่า Environment Table ของ Thread ที่ระบุ |
| `getgc(includeTables?)` | คืนค่าตาราง Objects ทั้งหมดที่อยู่ในระบบ Garbage Collector |
| `filtergc(type, options)` | คืนค่าตาราง Objects จาก Garbage Collector ที่ผ่านกรองตามเงื่อนไข |
| `getreg()` | คืนค่า Global Registry Table |

---

## 10. FileSystem Library

คำสั่งทั้งหมดประมวลผลไฟล์ภายในโฟลเดอร์ `workspace` ของ Executor:

| ฟังก์ชัน / เมธอด | คำอธิบายรายละเอียดและพารามิเตอร์ |
| :--- | :--- |
| `readfile(path)` | อ่านเนื้อหาภายในไฟล์ และคืนค่าเป็น `string` |
| `writefile(path, content)` | สร้างไฟล์ใหม่หรือทับไฟล์เดิมด้วยข้อความ `content` |
| `appendfile(path, content)` | เขียนข้อความเพิ่มต่อท้ายไฟล์เดิมที่มีอยู่ |
| `isfile(path)` | คืนค่า `boolean` เช็คว่า Path นั้นเป็นไฟล์หรือไม่ |
| `isfolder(path)` | คืนค่า `boolean` เช็คว่า Path นั้นเป็นโฟลเดอร์หรือไม่ |
| `listfiles(folderPath)` | คืนค่าตารางรายชื่อไฟล์ทั้งหมดภายในโฟลเดอร์นั้น |
| `makefolder(path)` | สร้างโฟลเดอร์ใหม่ตาม Path ที่ระบุ |
| `delfile(path)` | ลบไฟล์ที่กำหนดออกจากโฟลเดอร์ workspace |
| `delfolder(path)` | ลบโฟลเดอร์ที่กำหนด |
| `loadfile(path)` | โหลดสคริปต์จากไฟล์เข้าสู่ระบบ คอมไพล์เป็น chunk ฟังก์ชันพร้อมรัน |
| `dofile(path)` | โหลดและสั่งประมวลผล (Execute) โค้ดจากไฟล์ทันที |

---

## 11. Input Library (Input Simulation)

*ระบบจะจำลองการกดเฉพาะเมื่อ Roblox หน้าต่างเกมเปิดโฟกัส (`isrbxactive() == true`)*

* `isrbxactive()` : คืนค่า `boolean` ตรวจสอบว่าหน้าต่าง Roblox อยู่ในสถานะโฟกัสบนสุดหรือไม่
* `keypress(keycode)` / `keyrelease(keycode)` / `keytap(keycode)` : จำลองกดปุ่มคีย์บอร์ด, ปล่อยปุ่ม, หรือกดแล้วปล่อยทันที
* `mouse1click()` / `mouse1press()` / `mouse1release()` : จำลองคลิกซ้าย, กดคลิกซ้ายค้าง, ปล่อยคลิกซ้าย
* `mouse2click()` / `mouse2press()` / `mouse2release()` : จำลองคลิกขวา, กดคลิกขวาค้าง, ปล่อยคลิกขวา
* `mousemoveabs(x, y)` : ขยับเมาส์ไปยังพิกัดพิกเซล `(x, y)` บนหน้าจอแบบ Absolute
* `mousemoverel(dx, dy)` : ขยับเมาส์สัมพัทธ์ตามระยะ `(dx, dy)` จากตำแหน่งเมาส์ปัจจุบัน
* `mousescroll(amount)` : จำลองการเลื่อนลูกกลิ้งเมาส์ (Scroll wheel)

---

## 12. Instance Library

| ฟังก์ชัน / เมธอด | คำอธิบายรายละเอียดและพารามิเตอร์ |
| :--- | :--- |
| `fireclickdetector(clickDetector, distance?)` | สั่งยิงอีเวนต์ ClickDetector ทันทีโดยไม่ต้องเดินไปกด |
| `fireproximityprompt(prompt)` | สั่งยิงอีเวนต์ `Triggered` ของ ProximityPrompt ทันทีโดยไม่ต้องรอกดค้าง |
| `firetouchinterest(part1, part2, toggle)` | จำลองการชนกันของ Part (`toggle = 0` คือ Touched, `1` คือ TouchEnded) |
| `gethui()` | คืนค่า Hidden UI Container สำหรับสร้าง UI ที่สคริปต์ของเกมไม่สามารถตรวจจับหรือมองเห็นได้ |
| `getinstances()` | คืนค่าตารางของ `Instance` ทั้งหมดที่มีอยู่ในเกมขณะนั้น |
| `getnilinstances()` | คืนค่าตารางของ `Instance` ทั้งหมดที่ Parent ถูกตั้งเป็น `nil` |
| `getcallbackvalue(instance, property)` | คืนค่า Callback Function ที่ถูกผูกไว้กับ Callback Property |
| `getcustomasset(filePath)` | แปลงไฟล์รูปภาพ/เสียงในเครื่อง local ให้กลายเป็น Asset ID (`rbxasset://...`) |
| `getrendersteppedlist()` | คืนค่าตาราง Callback ทั้งหมดที่ถูกลงทะเบียนไว้ด้วย `BindToRenderStep` |

---

## 13. Oth Library (Off-Thread Hooking)

ระบบ **Off-Thread Hooking** เฉพาะของ Potassium ที่ออกแบบมาเพื่อ Hook C Functions บน Thread อิสระ เพื่อป้องกันการตรวจจับระบบ Hooking รูปแบบเดิม:

* `oth.hook(targetFunc, hookFunc)` : Hook ฟังก์ชันผ่านโครงสร้างการทำงาน Off-Thread อิสระ
* `oth.unhook(targetFunc)` : ยกเลิกการ Hook ของฟังก์ชันที่เคย Hook ไว้ด้วย `oth.hook`
* `oth.is_hook_thread()` : คืนค่า `boolean` เช็คว่า Thread ปัจจุบันเป็น Hook Thread หรือไม่
* `oth.get_original_thread()` : คืนค่า Thread ดั้งเดิมก่อนการ Hook
* `oth.get_root_callback()` : ดึงฟังก์ชันสำหรับเรียก Original Function ภายใต้ Context ของ Hook Thread

---

## 14. Metatable Library

| ฟังก์ชัน / เมธอด | คำอธิบายรายละเอียดและพารามิเตอร์ |
| :--- | :--- |
| `getrawmetatable(table/userdata)` | อ่านค่า Metatable โดยข้ามการบล็อกของ `__metatable` |
| `setrawmetatable(table/userdata, metatable)` | ตั้งค่า Metatable โดยข้ามการบล็อกของ `__metatable` |
| `hookmetamethod(object, method, newFunc)` | Hook เมธอดใน Metatable เช่น `"__index"`, `"__namecall"`, `"__newindex"` คืนค่าเดิม |
| `getnamecallmethod()` | ดึงชื่อเมธอดการเรียกแบบ Namecall ปัจจุบัน (เช่น `"FireServer"`, `"FindFirstChild"`) |
| `setnamecallmethod(methodName)` | กำหนดชื่อเมธอด `__namecall` ปัจจุบัน |
| `isreadonly(table)` | ตรวจสอบว่าตารางอยู่ในสถานะ Read-only หรือไม่ |
| `setreadonly(table, boolean)` | กำหนดสถานะ Read-only ของตาราง |
| `makereadonly(table)` | สั่งล็อกตารางให้เป็น Read-only ทันที |
| `makewritable(table)` | ปลดล็อกตารางให้แก้ไขข้อมูลได้ (Writable) |

---

## 15. Miscellaneous Library

| ฟังก์ชัน / เมธอด | คำอธิบายรายละเอียดและพารามิเตอร์ |
| :--- | :--- |
| `identifyexecutor()` | คืนค่า `name, version` (เช่น `"Potassium", "1.0.0"`) |
| `httpget(url)` | ส่งคำขอ HTTP GET Request ไปยัง URL และคืนค่าข้อมูลเป็นข้อความ |
| `request(options)` | ส่งคำขอ HTTP Custom Request รองรับ `Url`, `Method`, `Headers`, `Body` |
| `setclipboard(text)` | คัดลอกข้อความลงใน Windows Clipboard ของผู้ใช้ |
| `setrbxclipboard(text)` | คัดลอกข้อความเข้าสู่ Roblox Studio Clipboard |
| `queueonteleport(code)` | วางสคริปต์ตั้งคิวไว้ เพื่อรันอัตโนมัติเมื่อผู้เล่นเปลี่ยนแมป (Teleport) |
| `clearteleportqueue()` | ล้างคิวสคริปต์ Teleport ทั้งหมด |
| `saveinstance(options)` | บันทึกแมป/วัตถุ ออกมาเป็นไฟล์ `.rbxl` หรือ `.rbxm` |
| `gethwid()` | คืนค่าข้อความระบุตัวตนเครื่องฮาร์ดแวร์ของผู้ใช้ (Hardware ID) |
| `messagebox(text, caption, flags)` | สร้างป๊อบอัพ Windows Message Box แจ้งเตือน |
| `getfpscap()` / `setfpscap(cap)` | อ่านและตั้งค่าการจำกัดเฟรมเรต (FPS Cap) ของเกม |
| `getfflag(flag)` / `setfflag(flag, val)` | อ่านและแก้ไขค่า Fast Flag ของ Roblox Engine |
| `getfflagtype(flag)` | คืนค่าประเภท Data Type ของ Fast Flag |
| `getobjects(assetId)` | ดึง Objects จาก Roblox Asset Store (คล้าย `game:GetObjects`) |

---

## 16. PsmSignal Library

* `PsmSignal.new()` : สร้าง Custom Signal Object ตัวใหม่สำหรับใช้งานในสคริปต์
* `PsmConnection` : วัตถุ Connection ที่ได้จากการ `:Connect()` บน PsmSignal (มีเมธอด `:Disconnect()`)

---

## 17. RakNet Library (Network Packet Control)

ระบบเข้าถึง Packet เครือข่ายระดับล่างสุดผ่านโปรโตคอล RakNet:

* `raknet.add_send_hook(callback)` : ลงทะเบียน Hook เพื่อดักจับ/ดัดแปลง Packet ก่อนส่งไปยังเซิร์ฟเวอร์
* `raknet.remove_send_hook(callback)` : ลบ Send Hook ที่ลงทะเบียนไว้
* `raknet.add_receive_hook(callback)` : ลงทะเบียน Hook ดักจับ Packet ก่อนรับเข้ามาประมวลผลในเครื่อง
* `raknet.remove_receive_hook(callback)` : ลบ Receive Hook
* `raknet.send(payload, priority, reliability, channel)` : สร้างและส่ง Packet ปลอมไปยังเซิร์ฟเวอร์โดยตรง
* `RakNetPacket` : วัตถุแทนโครงสร้าง Packet ข้อมูลเครือข่าย

---

## 18. Reflection Library (Hidden Properties & Internal Data)

| ฟังก์ชัน / เมธอด | คำอธิบายรายละเอียดและพารามิเตอร์ |
| :--- | :--- |
| `gethiddenproperties(instance)` | คืนค่าตารางของ Non-scriptable Properties ทั้งหมดและค่าภายใน |
| `gethiddenproperty(instance, property)` | ดึงค่า Hidden Property และคืนค่า `value, isHidden` |
| `sethiddenproperty(instance, property, val)` | เปลี่ยนแปลงค่า Hidden Property ของ Instance |
| `getproperties(instance)` | ดึง Properties ทั้งหมดของ Instance (รวมทั้งปกติและที่ถูกซ่อน) |
| `isscriptable(instance, property)` | เช็คว่า Property นั้นยอมให้สคริปต์เข้าถึงได้หรือไม่ |
| `setscriptable(instance, property, bool)` | ปรับสถานะให้ Property สามารถอ่าน/เขียนได้จากสคริปต์ |
| `getsimulationradius()` / `setsimulationradius(r)` | อ่าน/ตั้งค่า รัศมีประมวลผลฟิสิกส์ (Simulation Radius) |
| `isnetworkowner(part)` | เช็คว่าผู้เล่นปัจจุบันเป็น Network Owner ของ Part หรือไม่ |
| `getbspval(instance, property)` | อ่านค่า BinaryString Property ที่ปกติเข้าถึงไม่ได้ (เช่น Terrain.SmoothGrid) |
| `getpcd(triangleMeshPart)` | คืนค่า 16-byte hash และ binary data ของ PhysicalConfigData |
| `getproximitypromptduration(prompt)` | อ่านระยะเวลาค้างกดของ ProximityPrompt |
| `setproximitypromptduration(prompt, duration)` | ปรับเปลี่ยนระยะเวลาการกดค้างของ ProximityPrompt |

---

## 19. Regex Library

* `Regex.new(pattern)` : สร้าง Regex Object สำหรับการค้นหาและแมตช์ข้อความตาม pattern
* `Regex.Escape(str)` : แปลงอักขระพิเศษในข้อความให้อยู่ในรูป Escape String สำหรับ Regex

---

## 20. Script Library

| ฟังก์ชัน / เมธอด | คำอธิบายรายละเอียดและพารามิเตอร์ |
| :--- | :--- |
| `getscripts()` | คืนค่าตารางของ Script ทั้งหมดที่มีอยู่ในเกม |
| `getrunningscripts()` | คืนค่าตารางของ Script ทั้งหมดที่กำลังรันอยู่ในขณะนั้น |
| `getloadedmodules()` | คืนค่าตารางของ `ModuleScript` ทั้งหมดที่ถูกโหลดแล้ว |
| `getscriptbytecode(script)` | ดึงค่า Raw Bytecode ของ Script |
| `getscriptclosure(script)` | ดึงค่า Main Function/Closure ของ Script |
| `getscriptfromthread(thread)` | ดึงสคริปต์ต้นทางจาก Thread ที่ระบุ |
| `getscriptthread(script)` | ดึง Thread ที่ผูกอยู่กับ Script |
| `getcallingscript()` | คืนค่า Script ที่เป็นตัวสั่งประมวลผลโค้ดปัจจุบัน |
| `getscripthash(script)` | คืนค่า Hash ของ Script |
| `getthreadidentity()` | คืนค่าระดับสิทธิ์ Identity ปัจจุบันของ Thread (เช่น Identity 8) |
| `setthreadidentity(identityNumber)` | เปลี่ยนระดับสิทธิ์ Identity ของ Thread |
| `dumpbytecode(func)` | แปลงฟังก์ชัน Lua ให้ออกมาเป็น Luau Bytecode Format |
| `decompile(script)` | ถอดรหัสย้อนกลับจาก Bytecode ของ Script ให้กลายเป็นข้อความโค้ด Luau |

---

## 21. Signal Library

| ฟังก์ชัน / เมธอด | คำอธิบายรายละเอียดและพารามิเตอร์ |
| :--- | :--- |
| `firesignal(signal, ...args)` | สั่งยิงสัญญาณ (Fire) Connections ทั้งหมดที่เชื่อมกับ `RBXScriptSignal` ทันที |
| `replicatesignal(signal, ...args)` | สั่งยิงสัญญาณส่งไปยังเซิร์ฟเวอร์ (Server Replication) |
| `getconnections(signal)` | คืนค่าตารางของวัตถุ `Connection` ทั้งหมดที่เชื่อมอยู่กับ Signal |
| `getconnection(signal, index)` | ดึงวัตถุ Connection เดี่ยวจาก Signal ตามตำแหน่ง Index |
| `cansignalreplicate(signal)` | ตรวจสอบว่า Signal สามารถ Replicate ไปยังเซิร์ฟเวอร์ได้หรือไม่ |
| `getsignalarguments(signal)` | คืนค่าตารางประเภท Data Types ที่ Signal นั้นคาดหวังจะรับ |
| `getsignalargumentsinfo(signal)` | คืนค่าข้อมูล Argument อย่างละเอียดสำหรับใช้ทำ Signal Replication |
| `getsignalwhitelist()` | คืนค่าตารางรายชื่อ Signal ที่อยู่ใน Replication Whitelist ของ Roblox |

---

## 22. WebSocket Library

* `WebSocket.connect(url)` : สร้างการเชื่อมต่อแบบเรียลไทม์ผ่านโปรโตคอล WebSocket (คืนค่าเป็น `WebSocket` object ที่มีเมธอด `:Send(msg)`, `:Close()`, และอีเวนต์ `OnMessage`, `OnClose`)

---

