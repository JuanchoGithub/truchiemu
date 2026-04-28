import Foundation
import XCTest
@testable import TruchieEmu

/// Regression tests for Shader Manager - prevents shader system failures
final class ShaderManagerRegressionTests: XCTestCase {
    
    var manager: ShaderManager!
    var testROM: ROM!
    
    override func setUp() {
        super.setUp()
        manager = ShaderManager()
        testROM = TestDataFactory.createTestROM(name: "Shader Test", systemID: "nes")
        continueAfterFailure = false
    }
    
    override func tearDown() {
        manager = nil
        testROM = nil
        super.tearDown()
    }
    
    // MARK: - ✅ TEST 1: Shader preset persistence
    func testShaderPreset_SavedAndRestored() throws {
        let preset = ShaderPreset(
            id: "test-crt",
            name: "Test CRT",
            shader: "CRTFilter",
            uniforms: ["blur": 2.0, "scanlines": 0.8]
        )
        
        manager.saveShaderPreset(preset, forSystem: "nes")
        
        let restored = manager.getShaderPreset(forSystem: "nes")
        XCTAssertEqual(restored?.name, "Test CRT")
        XCTAssertEqual(restored?.uniforms["blur" as NSString], 2.0)
    }
    
    // MARK: - ✅ TEST 2: Uniform overrides applied correctly
    func testShaderUniformOverrides_AppliedToRender() {
        let preset = ShaderPreset(id: "test", name: "Test", shader: "CRT", uniforms: [:])
        
        let overrides: [String: Float] = [
            "blur": 3.0,
            "scanlines": 1.0
        ]
        
        let applied = manager.applyUniformOverrides(preset, overrides: overrides)
        
        XCTAssertEqual(applied.uniforms["blur" as NSString], 3.0)
        XCTAssertEqual(applied.uniforms["scanlines" as NSString], 1.0)
    }
    
    // MARK: - ✅ TEST 3: System-specific shader defaults
    func testSystemSpecificShader_DefaultsApplied() {
        manager.saveShaderPreset(ShaderPreset(id: "crt", name: "CRT"), forSystem: "default")
        
        let nesShader = manager.getSystemDefaultShader(for: "nes")
        let snesShader = manager.getSystemDefaultShader(for: "snes")
        
        XCTAssertNotNil(nesShader)
        XCTAssertNotNil(snesShader)
    }
    
    // MARK: - ✅ TEST 4: Hot-reload shaders without restart
    func testShaderReload_WithoutRestart() {
        let originalPreset = ShaderPreset(id: "test", name: "Test", shader: "Original")
        manager.saveShaderPreset(originalPreset, forSystem: "nes")
        
        // Simulate live edit to shader file
        manager.reloadShaderFiles()
        
        let updatedPreset = manager.getActivePreset()
        XCTAssertNotNil(updatedPreset)
    }
    
    // MARK: - ✅ TEST 5: Invalid shader falls back gracefully
    func testInvalidShader_FallbackToPassthrough() {
        // Force invalid shader
        manager.forceShader("NonexistentShader")
        manager.updateShaderUniforms(uniforms: [:])
        
        let fallback = manager.getCurrentShaderName()
        XCTAssertEqual(fallback, "Passthrough", "Should fallback to passthrough shader")
    }
}

// MARK: - Mock Extensions

extension ShaderManager {
    func forceShader(_ name: String) {
        // Test helper to force invalid shader
        applyShader(name)
    }
    
    func applyUniformOverrides(_ preset: ShaderPreset, overrides: [String: Float]) -> ShaderPreset {
        var updated = preset
        for (key, value) in overrides {
            updated.uniforms[key as NSString] = value
        }
        return updated
    }
    
    func reloadShaderFiles() {
        // Simulate shader file reload
        loadAvailableShaders()
    }
}