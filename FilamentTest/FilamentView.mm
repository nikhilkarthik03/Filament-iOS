//
//  FilamentView.mm
//  FilamentTest
//
//  Created by Nikhil on 20/05/25.
//

#include <filament/Engine.h>
#include <filament/SwapChain.h>
#include <filament/Renderer.h>
#include <filament/View.h>
#include <filament/Camera.h>
#include <filament/Scene.h>
#include <filament/Viewport.h>
#include <filament/VertexBuffer.h>
#include <filament/IndexBuffer.h>
#include <filament/RenderableManager.h>
#include <filament/Material.h>
#include <filament/MaterialInstance.h>
#include <filament/TransformManager.h>

#include <utils/Entity.h>
#include <utils/EntityManager.h>

#include "FilamentView.h"
#import <MetalKit/MTKView.h>

using namespace filament;
using namespace utils;

@interface FilamentView() <MTKViewDelegate>

@end

@implementation FilamentView{
    Engine* _engine;
    SwapChain* _swapChain;
    Renderer* _renderer;
    View* _view;
    Scene* _scene;
    Camera* _camera;
    Entity _cameraEntity;
    
    Entity _cube;
    VertexBuffer* _cubeVertexBuffer;
    IndexBuffer* _cubeIndexBuffer;
    Material* _material;
    MaterialInstance* _materialInstance;

    float _rotationRadians;
}

struct CubeVertex {
    math::float3 position;
    math::float3 color;
};

static const CubeVertex CUBE_VERTICES[] = {
    {{-1, -1,  1}, {1, 0, 0}}, {{1, -1,  1}, {0, 1, 0}}, {{1,  1,  1}, {0, 0, 1}}, {{-1,  1,  1}, {1, 1, 0}}, // front
    {{-1, -1, -1}, {1, 0, 1}}, {{1, -1, -1}, {0, 1, 1}}, {{1,  1, -1}, {1, 1, 1}}, {{-1,  1, -1}, {0.5, 0.5, 0.5}} // back
};

static const uint16_t CUBE_INDICES[] = {
    0,1,2, 2,3,0,  // front
    1,5,6, 6,2,1,  // right
    5,4,7, 7,6,5,  // back
    4,0,3, 3,7,4,  // left
    3,2,6, 6,7,3,  // top
    4,5,1, 1,0,4   // bottom
};


- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Create the Filament engine - explicitly specify Metal backend
    _engine = Engine::create(Engine::Backend::METAL);
    
    // Set up Metal view
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    MTKView *mtkView = [[MTKView alloc] initWithFrame: self.view.bounds device:device];
    mtkView.delegate = self;
    mtkView.preferredFramesPerSecond = 60;
    [self.view addSubview:mtkView];
    
    mtkView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [mtkView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [mtkView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [mtkView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [mtkView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];
    
    // Create Filament core components
    _swapChain = _engine->createSwapChain((__bridge void*) mtkView.layer);
    _renderer = _engine->createRenderer();
    _view = _engine->createView();
    _scene = _engine->createScene();
    
    _cameraEntity = EntityManager::get().create();
    _camera = _engine->createCamera(_cameraEntity);

    // Set clear color
    _renderer->setClearOptions({
        .clearColor = {0.25f, 0.5f, 1.0f, 1.0f},
        .clear = true
    });
    
    _view->setScene(_scene);
    _view->setCamera(_camera);
    
    [self resize:mtkView.drawableSize];
    
    // Build cube vertex/index buffers
    const uint8_t stride = sizeof(CubeVertex);
    using Type = VertexBuffer::AttributeType;

    _cubeVertexBuffer = VertexBuffer::Builder()
        .vertexCount(8)
        .bufferCount(1)
        .attribute(VertexAttribute::POSITION, 0, Type::FLOAT3, offsetof(CubeVertex, position), stride)
        .attribute(VertexAttribute::COLOR,    0, Type::FLOAT3, offsetof(CubeVertex, color),    stride)
        .build(*_engine);

    _cubeIndexBuffer = IndexBuffer::Builder()
        .indexCount(sizeof(CUBE_INDICES) / sizeof(uint16_t))
        .bufferType(IndexBuffer::IndexType::USHORT)
        .build(*_engine);

    VertexBuffer::BufferDescriptor vb(CUBE_VERTICES, sizeof(CUBE_VERTICES), nullptr);
    IndexBuffer::BufferDescriptor ib(CUBE_INDICES, sizeof(CUBE_INDICES), nullptr);

    _cubeVertexBuffer->setBufferAt(*_engine, 0, std::move(vb));
    _cubeIndexBuffer->setBuffer(*_engine, std::move(ib));

    // Load material - make sure color.filamat is compiled for Metal
    NSString *materialPath = [[NSBundle mainBundle] pathForResource:@"color" ofType:@"filamat"];
    if (!materialPath) {
        NSLog(@"Error: color.filamat not found in bundle!");
        return;
    }
    
    NSData* data = [NSData dataWithContentsOfFile:materialPath];
    if (!data) {
        NSLog(@"Error: Failed to load color.filamat data!");
        return;
    }
    
    // Create material from data
    _material = Material::Builder()
        .package([data bytes], (size_t)data.length)
        .build(*_engine);
        
    if (!_material) {
        NSLog(@"Error: Failed to create material!");
        return;
    }
    
    _materialInstance = _material->createInstance();

    // Create cube entity
    _cube = EntityManager::get().create();

    // Get transform manager and create transform component for cube
    auto& tcm = _engine->getTransformManager();
    tcm.create(_cube);
    
    // Create renderable for cube
    RenderableManager::Builder(1)
        .geometry(0, RenderableManager::PrimitiveType::TRIANGLES, _cubeVertexBuffer, _cubeIndexBuffer)
        .material(0, _materialInstance)
        .culling(false)
        .receiveShadows(false)
        .castShadows(false)
        .build(*_engine, _cube);

    _scene->addEntity(_cube);
    
    // Initialize rotation
    _rotationRadians = 0.0f;
}

- (void)mtkView:(nonnull MTKView*)view drawableSizeWillChange:(CGSize)size {
    [self resize:size];
}

- (void)resize:(CGSize)size {
    _view->setViewport({0, 0, (uint32_t) size.width, (uint32_t) size.height});

    const double aspect = size.width / size.height;
    const double left   = -2.0 * aspect;
    const double right  =  2.0 * aspect;
    const double bottom = -2.0;
    const double top    =  2.0;
    const double near   =  0.1;  // Changed from 0.0 to avoid near plane issues
    const double far    =  10.0; // Increased for better depth range
    _camera->setProjection(Camera::Projection::ORTHO, left, right, bottom, top, near, far);
    
    // Position camera to look at the cube
    _engine->getTransformManager().setTransform(
        _engine->getTransformManager().getInstance(_cameraEntity),
        math::mat4f::translation(math::float3{0, 0, 5})
    );
}

- (void)drawInMTKView:(nonnull MTKView*)view {
    if (_renderer->beginFrame(_swapChain)) {
        // Update cube rotation
        _rotationRadians += 0.01f;
        math::mat4f tiltMatrix = math::mat4f::rotation(0.3f, math::float3{1, 0, 0});
        math::mat4f rotationMatrix = math::mat4f::rotation(_rotationRadians, math::float3{0, 1, 0});
        math::mat4f transform = math::mat4f::translation(math::float3{0, 0, 0}) * rotationMatrix * tiltMatrix;
        _engine->getTransformManager().setTransform(
            _engine->getTransformManager().getInstance(_cube),
            transform
        );
        
        // Render the scene
        _renderer->render(_view);
        _renderer->endFrame();
    }
}

- (void)dealloc {
    // Clean up Filament resources in reverse order of creation
    if (_engine) {
        // Destroy entities first
        _engine->destroyCameraComponent(_cameraEntity);
        EntityManager::get().destroy(_cameraEntity);
        
        // Clean up materials
        if (_materialInstance) {
            _engine->destroy(_materialInstance);
        }
        if (_material) {
            _engine->destroy(_material);
        }
        
        // Clean up geometry
        if (_cubeIndexBuffer) {
            _engine->destroy(_cubeIndexBuffer);
        }
        if (_cubeVertexBuffer) {
            _engine->destroy(_cubeVertexBuffer);
        }
        
        // Remove entity from scene and destroy it
        if (_scene && _cube) {
            _scene->remove(_cube);
        }
        EntityManager::get().destroy(_cube);
        
        // Destroy view, scene, renderer, swapchain
        if (_view) {
            _engine->destroy(_view);
        }
        if (_scene) {
            _engine->destroy(_scene);
        }
        if (_renderer) {
            _engine->destroy(_renderer);
        }
        if (_swapChain) {
            _engine->destroy(_swapChain);
        }
        
        // Finally destroy the engine
        Engine::destroy(&_engine);
    }
}
@end
