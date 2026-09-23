///|
#external
priv type CFile

///|
#borrow(ptr)
extern "c" fn is_null(ptr : CFile) -> Int = "moonbit_is_null"

///|
#borrow(path, mode)
extern "c" fn fopen_ffi(path : Bytes, mode : Bytes) -> CFile = "moonbit_fopen_ffi"

///|
#borrow(ptr, stream)
extern "c" fn fread_ffi(
  ptr : Bytes,
  size : Int,
  count : Int,
  stream : CFile,
) -> Int = "moonbit_fread_ffi"

///|
extern "c" fn make_bytes_raw(length : Int) -> Bytes = "moonbit_make_bytes_raw"

///|
#borrow(stream)
extern "c" fn fseek_ffi(stream : CFile, offset : Int, whence : Int) -> Int = "moonbit_fseek_ffi"

///|
#borrow(stream)
extern "c" fn ftell_ffi(stream : CFile) -> Int = "moonbit_ftell_ffi"

///|
#borrow(stream)
extern "c" fn fclose_ffi(stream : CFile) -> Int = "moonbit_fclose_ffi"

///|
fn c_string(value : String) -> Bytes {
  let encoded = @utf8.encode(value)
  let result = FixedArray::make(encoded.length() + 1, b'\x00')
  for i in 0..<encoded.length() {
    result[i] = encoded[i]
  }
  result.unsafe_reinterpret_as_bytes()
}

///|
fn read_file(path : String) -> String? {
  let file = fopen_ffi(c_string(path), c_string("rb"))
  if is_null(file) != 0 {
    return None
  }
  ignore(fseek_ffi(file, 0, 2))
  let length = ftell_ffi(file)
  ignore(fseek_ffi(file, 0, 0))
  if length < 0 {
    ignore(fclose_ffi(file))
    return None
  }
  let buffer = make_bytes_raw(length)
  let count = fread_ffi(buffer, 1, length, file)
  ignore(fclose_ffi(file))
  Some(@utf8.decode_lossy(buffer.view(start=0, end=count).to_owned()))
}
