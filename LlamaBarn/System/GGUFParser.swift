//
//  GGUFParser.swift
//  LlamaBarn
//
//  Created by Kilo on 03/04/2026.
//

import Foundation
import CommonCrypto

enum GGUFError: Error {
    case invalidMagic
    case invalidVersion
    case readError
    case unsupportedType
}

struct GGUFMetadata {
    let architecture: String?
    let parameterCount: UInt64?
    let fileType: UInt32?
    let name: String?
    let description: String?
    let contextLength: UInt64?
    let fileSize: UInt64
    let embeddingLength: UInt64?
    let attentionHeadCount: UInt64?
    let attentionHeadCountKv: UInt64?
    let quantization: String?
    
    var quantizationLabel: String {
        if let q = quantization, !q.isEmpty { return q }
        guard let ft = fileType else { return "Unknown" }
        switch ft {
        case 0: return "FP32"
        case 1: return "FP16"
        case 2: return "Q4_0"
        case 3: return "Q4_1"
        case 6: return "Q5_0"
        case 7: return "Q5_1"
        case 8: return "Q8_0"
        case 9: return "Q8_1"
        case 10: return "Q2_K"
        case 11: return "Q3_K"
        case 12: return "Q4_K"
        case 13: return "Q5_K"
        case 14: return "Q6_K"
        case 15: return "Q8_K"
        case 16: return "IQ2_XXS"
        case 17: return "IQ2_XS"
        case 18: return "IQ3_XXS"
        case 19: return "IQ1_S"
        case 20: return "IQ4_NL"
        case 21: return "IQ3_S"
        case 22: return "IQ2_S"
        case 23: return "IQ4_XS"
        default: return "Q?"
        }
    }
    
    var sizeLabel: String {
        guard let pc = parameterCount else {
            return String(format: "%.1f GB", Double(fileSize) / 1_073_741_824)
        }
        if pc < 1_000_000_000 {
            return String(format: "%.1f B", Double(pc) / 1_000_000_000)
        }
        return String(format: "%.0f B", Double(pc) / 1_000_000_000)
    }
    
    var familyName: String {
        guard let arch = architecture else { return "Unknown" }
        return GGUFMetadata.architectureToFamily(arch)
    }
    
    static func architectureToFamily(_ arch: String) -> String {
        switch arch.lowercased() {
        case "llama": return "LLaMA"
        case "qwen2", "qwen3", "qwen2moe", "qwen3moe": return "Qwen"
        case "gemma", "gemma2", "gemma3": return "Gemma"
        case "mistral", "mixtral": return "Mistral"
        case "phi2", "phi3", "phi4": return "Phi"
        case "gpt2": return "GPT-2"
        case "gptj", "gpt_j": return "GPT-J"
        case "gptneox", "gpt_neox": return "GPT-NeoX"
        case "mamba": return "Mamba"
        case "command-r", "commandr": return "Command-R"
        case "cohere": return "Cohere"
        case "deepseek2", "deepseek3": return "DeepSeek"
        case "granite": return "Granite"
        case "olmo": return "OLMo"
        case "stablelm": return "StableLM"
        case "falcon": return "Falcon"
        case "bert", "nomic-bert": return "BERT"
        default: return arch.capitalized
        }
    }
    
    var ctxBytesPer1kTokensEstimate: Int {
        guard let dModel = embeddingLength, dModel > 0 else {
            return estimateFromParameterCount()
        }
        let heads = attentionHeadCount ?? 32
        let headDim = dModel / heads
        let kvHeads = attentionHeadCountKv ?? heads
        let bytesPerToken = 2 * kvHeads * headDim * 2
        return Int(bytesPerToken)
    }
    
    private func estimateFromParameterCount() -> Int {
        guard let pc = parameterCount else { return 64 * 1024 }
        let billions = Double(pc) / 1_000_000_000.0
        if billions < 3 { return 16 * 1024 }
        if billions < 13 { return 32 * 1024 }
        if billions < 70 { return 64 * 1024 }
        return 128 * 1024
    }
}

enum GGUFParser {
    static func parseHeader(at path: String) throws -> GGUFMetadata {
        let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: path))
        defer { try? fileHandle.close() }
        
        // Read magic (4 bytes)
        let magicData = fileHandle.readData(ofLength: 4)
        guard magicData.count == 4 else { throw GGUFError.readError }
        
        let magic = magicData.withUnsafeBytes { $0.load(as: UInt32.self) }
        guard magic == 0x46554747 /* "GGUF" */ else { throw GGUFError.invalidMagic }
        
        // Read version
        let versionData = fileHandle.readData(ofLength: 4)
        let version = versionData.withUnsafeBytes { $0.load(as: UInt32.self) }
        guard version >= 1 && version <= 3 else { throw GGUFError.invalidVersion }
        
        // Read tensor count and kv count
        let tensorCountData = fileHandle.readData(ofLength: 8)
        let _ = tensorCountData.withUnsafeBytes { $0.load(as: UInt64.self) }
        
        let kvCountData = fileHandle.readData(ofLength: 8)
        let kvCount = kvCountData.withUnsafeBytes { $0.load(as: UInt64.self) }
        
        var architecture: String?
        var parameterCount: UInt64?
        var fileType: UInt32?
        var name: String?
        var description: String?
        var contextLength: UInt64?
        var embeddingLength: UInt64?
        var attentionHeadCount: UInt64?
        var attentionHeadCountKv: UInt64?
        var quantization: String?
        
        // Parse kv pairs
        for _ in 0..<kvCount {
            let keyLenData = fileHandle.readData(ofLength: 8)
            let keyLen = keyLenData.withUnsafeBytes { $0.load(as: UInt64.self) }
            
            let keyData = fileHandle.readData(ofLength: Int(keyLen))
            guard let key = String(data: keyData, encoding: .utf8) else {
                // Skip invalid key, advance file pointer
                let typeData = fileHandle.readData(ofLength: 4)
                let valueType = typeData.withUnsafeBytes { $0.load(as: UInt32.self) }
                let _ = skipValue(of: valueType, handle: fileHandle)
                continue
            }
            
            let typeData = fileHandle.readData(ofLength: 4)
            let valueType = typeData.withUnsafeBytes { $0.load(as: UInt32.self) }
            
            switch key {
            case "general.architecture":
                architecture = try readString(from: fileHandle)
            case "general.parameter_count":
                parameterCount = try readUInt64(from: fileHandle)
            case "general.file_type":
                fileType = try readUInt32(from: fileHandle)
            case "general.name":
                name = try readString(from: fileHandle)
            case "general.description":
                description = try readString(from: fileHandle)
            case "general.quantization":
                quantization = try readString(from: fileHandle)
            case "llama.context_length":
                contextLength = try readUInt64(from: fileHandle)
            case "llama.embedding_length":
                embeddingLength = try readUInt64(from: fileHandle)
            case "llama.attention.head_count":
                attentionHeadCount = try readUInt64(from: fileHandle)
            case "llama.attention.head_count_kv":
                attentionHeadCountKv = try readUInt64(from: fileHandle)
            default:
                let _ = skipValue(of: valueType, handle: fileHandle)
            }
        }
        
        let attr = try FileManager.default.attributesOfItem(atPath: path)
        let fileSize = (attr[.size] as? NSNumber)?.uint64Value ?? 0
        
        return GGUFMetadata(
            architecture: architecture,
            parameterCount: parameterCount,
            fileType: fileType,
            name: name,
            description: description,
            contextLength: contextLength,
            fileSize: fileSize,
            embeddingLength: embeddingLength,
            attentionHeadCount: attentionHeadCount,
            attentionHeadCountKv: attentionHeadCountKv,
            quantization: quantization
        )
    }
    
    private static func readString(from handle: FileHandle) throws -> String {
        let lenData = handle.readData(ofLength: 8)
        let len = lenData.withUnsafeBytes { $0.load(as: UInt64.self) }
        let data = handle.readData(ofLength: Int(len))
        return String(data: data, encoding: .utf8) ?? ""
    }
    
    private static func readUInt32(from handle: FileHandle) throws -> UInt32 {
        let data = handle.readData(ofLength: 4)
        return data.withUnsafeBytes { $0.load(as: UInt32.self) }
    }
    
    private static func readUInt64(from handle: FileHandle) throws -> UInt64 {
        let data = handle.readData(ofLength: 8)
        return data.withUnsafeBytes { $0.load(as: UInt64.self) }
    }
    
    @discardableResult
    private static func skipValue(of type: UInt32, handle: FileHandle) -> Int {
        switch type {
        case 0: // uint8
            handle.readData(ofLength: 1)
            return 1
        case 1: // int8
            handle.readData(ofLength: 1)
            return 1
        case 2: // uint16
            handle.readData(ofLength: 2)
            return 2
        case 3: // int16
            handle.readData(ofLength: 2)
            return 2
        case 4: // uint32
            handle.readData(ofLength: 4)
            return 4
        case 5: // int32
            handle.readData(ofLength: 4)
            return 4
        case 6: // float32
            handle.readData(ofLength: 4)
            return 4
        case 7: // bool
            handle.readData(ofLength: 1)
            return 1
        case 8: // string
            let lenData = handle.readData(ofLength: 8)
            let len = lenData.withUnsafeBytes { $0.load(as: UInt64.self) }
            handle.readData(ofLength: Int(len))
            return 8 + Int(len)
        case 9: // array
            let typeData = handle.readData(ofLength: 4)
            let elemType = typeData.withUnsafeBytes { $0.load(as: UInt32.self) }
            let lenData = handle.readData(ofLength: 8)
            let len = lenData.withUnsafeBytes { $0.load(as: UInt64.self) }
            var total = 12
            for _ in 0..<len {
                total += skipValue(of: elemType, handle: handle)
            }
            return total
        case 10: // uint64
            handle.readData(ofLength: 8)
            return 8
        case 11: // int64
            handle.readData(ofLength: 8)
            return 8
        case 12: // float64
            handle.readData(ofLength: 8)
            return 8
        default:
            return 0
        }
    }
}
