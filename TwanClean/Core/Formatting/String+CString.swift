extension String {
    /// Decodes a NUL-terminated C string buffer, such as one filled by
    /// `proc_pidpath` or read from `dirent.d_name`. Invalid UTF-8 is repaired.
    init(nulTerminated buffer: [CChar]) {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        self.init(decoding: bytes, as: UTF8.self)
    }
}
