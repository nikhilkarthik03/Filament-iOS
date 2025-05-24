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
#include <filament/LightManager.h>

#include <utils/Entity.h>
#include <utils/EntityManager.h>

#include "FilamentView.h"
#import <MetalKit/MTKView.h>

using namespace filament;
using namespace utils;

@interface FilamentView() <MTKViewDelegate>

@end

@implementation FilamentView {
    Engine* _engine;
    SwapChain* _swapChain;
    Renderer* _renderer;
    View* _view;
    Scene* _scene;
    Camera* _camera;
    Entity _cameraEntity;
    
    Entity _cube;
    Entity _light;
    Entity _light2;
    VertexBuffer* _cubeVertexBuffer;
    IndexBuffer* _cubeIndexBuffer;
    Material* _material;
    MaterialInstance* _materialInstance;

    float _rotationRadians;
}

struct CubeVertex {
    math::float3 position;
    math::float3 normal;
    math::float4 tangent;
};

// Helper function to compute proper tangent vectors
math::float4 computeTangent(const math::float3& normal) {
    math::float3 tangent;
    
    // Choose a vector that's not parallel to the normal
    if (abs(normal.x) > 0.9f) {
        tangent = normalize(cross(normal, math::float3(0, 1, 0)));
    } else {
        tangent = normalize(cross(normal, math::float3(1, 0, 0)));
    }
    
    // Return tangent with w=1 (positive handedness)
    return math::float4(tangent.x, tangent.y, tangent.z, 1.0f);
}

static CubeVertex CUBE_VERTICES[] = {
    // Front face (+Z)
    {{-1, -1,  1}, {0, 0, 1}, {}},
    {{1, -1,  1},  {0, 0, 1}, {}},
    {{1,  1,  1},  {0, 0, 1}, {}},
    {{-1,  1,  1}, {0, 0, 1}, {}},

    // Right face (+X)
    {{1, -1,  1},  {1, 0, 0}, {}},
    {{1, -1, -1},  {1, 0, 0}, {}},
    {{1,  1, -1},  {1, 0, 0}, {}},
    {{1,  1,  1},  {1, 0, 0}, {}},

    // Back face (-Z)
    {{1, -1, -1},  {0, 0, -1}, {}},
    {{-1, -1, -1}, {0, 0, -1}, {}},
    {{-1,  1, -1}, {0, 0, -1}, {}},
    {{1,  1, -1},  {0, 0, -1}, {}},

    // Left face (-X)
    {{-1, -1, -1}, {-1, 0, 0}, {}},
    {{-1, -1,  1}, {-1, 0, 0}, {}},
    {{-1,  1,  1}, {-1, 0, 0}, {}},
    {{-1,  1, -1}, {-1, 0, 0}, {}},

    // Top face (+Y)
    {{-1,  1,  1}, {0, 1, 0}, {}},
    {{1,  1,  1},  {0, 1, 0}, {}},
    {{1,  1, -1},  {0, 1, 0}, {}},
    {{-1,  1, -1}, {0, 1, 0}, {}},

    // Bottom face (-Y)
    {{-1, -1, -1}, {0, -1, 0}, {}},
    {{1, -1, -1},  {0, -1, 0}, {}},
    {{1, -1,  1},  {0, -1, 0}, {}},
    {{-1, -1,  1}, {0, -1, 0}, {}},
};

static const uint16_t CUBE_INDICES[] = {
    0, 1, 2,  2, 3, 0,      // front
    4, 5, 6,  6, 7, 4,      // right
    8, 9,10, 10,11, 8,      // back
   12,13,14, 14,15,12,      // left
   16,17,18, 18,19,16,      // top
   20,21,22, 22,23,20       // bottom
};

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupMetal];
    }
    return self;
}

-(void)setupMetal {
    _engine = Engine::create(Engine::Backend::METAL);
    
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    MTKView *mtkView = [[MTKView alloc] initWithFrame:self.bounds device:device];
    mtkView.delegate = self;
    mtkView.preferredFramesPerSecond = 60;
    [self addSubview:mtkView];
    
    mtkView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [mtkView.topAnchor constraintEqualToAnchor:self.topAnchor],
        [mtkView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [mtkView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [mtkView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
    ]];
    
    _swapChain = _engine->createSwapChain((__bridge void*)mtkView.layer);
    _renderer = _engine->createRenderer();
    _view = _engine->createView();
    _scene = _engine->createScene();
    
    _cameraEntity = EntityManager::get().create();
    _camera = _engine->createCamera(_cameraEntity);
    
    _renderer->setClearOptions({
        .clearColor = {0.25f, 0.5f, 1.0f, 1.0f},
        .clear = true
    });
    
    _view->setScene(_scene);
    _view->setCamera(_camera);
    
    [self resize:mtkView.drawableSize];
    
    // Compute tangent vectors for all vertices
    for (int i = 0; i < 24; i++) {
        CUBE_VERTICES[i].tangent = computeTangent(CUBE_VERTICES[i].normal);
    }
    
    _cubeVertexBuffer = VertexBuffer::Builder()
        .vertexCount(24)
        .bufferCount(1)
        .attribute(VertexAttribute::POSITION, 0, VertexBuffer::AttributeType::FLOAT3, offsetof(CubeVertex, position), sizeof(CubeVertex))
        .attribute(VertexAttribute::TANGENTS, 0, VertexBuffer::AttributeType::FLOAT4, offsetof(CubeVertex, tangent), sizeof(CubeVertex))
        .build(*_engine);

    
    _cubeIndexBuffer = IndexBuffer::Builder()
        .indexCount(sizeof(CUBE_INDICES) / sizeof(uint16_t))
        .bufferType(IndexBuffer::IndexType::USHORT)
        .build(*_engine);
    
    VertexBuffer::BufferDescriptor vb(CUBE_VERTICES, sizeof(CUBE_VERTICES), nullptr);
    IndexBuffer::BufferDescriptor ib(CUBE_INDICES, sizeof(CUBE_INDICES), nullptr);
    
    _cubeVertexBuffer->setBufferAt(*_engine, 0, std::move(vb));
    _cubeIndexBuffer->setBuffer(*_engine, std::move(ib));
    
    // Load material (color.filamat must be included in your bundle)
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
    
    _material = Material::Builder()
        .package([data bytes], (size_t)data.length)
        .build(*_engine);
    
    if (!_material) {
        NSLog(@"Error: Failed to create material!");
        return;
    }
    
    _materialInstance = _material->createInstance();
    _materialInstance->setParameter("baseColor", filament::math::float4{1.0f, 0.0f, 0.0f, 1.0f});
    _materialInstance->setParameter("roughness", 0.4f);
    _materialInstance->setParameter("metallic", 0.0f);
    
    _cube = EntityManager::get().create();
    
    auto& tcm = _engine->getTransformManager();
    tcm.create(_cube);
    
    RenderableManager::Builder(1)
        .geometry(0, RenderableManager::PrimitiveType::TRIANGLES, _cubeVertexBuffer, _cubeIndexBuffer)
        .material(0, _materialInstance)
        .culling(false)
        .receiveShadows(false)
        .castShadows(false)
        .build(*_engine, _cube);
    
    _scene->addEntity(_cube);
    
    // Create a directional light that points toward the cube from a better angle
    _light = EntityManager::get().create();
    LightManager::Builder(LightManager::Type::DIRECTIONAL)
        .color({1.0f, 1.0f, 1.0f})
        .intensity(100000.0f)
        .direction({0.0f, 0.7f, 0.7f})
        .castShadows(false)
        .build(*_engine, _light);
    
    _scene->addEntity(_light);
    
    // Add some ambient/fill light
    _light2 = EntityManager::get().create();
    LightManager::Builder(LightManager::Type::DIRECTIONAL)
        .color({0.6f, 0.7f, 1.0f})
        .intensity(20000.0f)
        .direction({0.5f, 0.3f, 0.8f})
        .castShadows(false)
        .build(*_engine, _light2);
    
    _scene->addEntity(_light2);
    
    _rotationRadians = 0.0f;
    
    UIButton *colorButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [colorButton setTitle:@"Change Cube Color" forState:UIControlStateNormal];
    colorButton.frame = CGRectMake(20, 40, 180, 40);
    colorButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.7];
    colorButton.layer.cornerRadius = 5;
    [colorButton addTarget:self action:@selector(changeCubeColor) forControlEvents:UIControlEventTouchUpInside];

    [self addSubview:colorButton];
}

- (void)changeCubeColor {
    // Random color example
    float r = (float)arc4random_uniform(256) / 255.0f;
    float g = (float)arc4random_uniform(256) / 255.0f;
    float b = (float)arc4random_uniform(256) / 255.0f;

    _materialInstance->setParameter("baseColor", filament::math::float4{r, g, b, 1.0f});
    NSLog(@"Cube color changed to: R=%.2f G=%.2f B=%.2f", r, g, b);
}

- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size {
    [self resize:size];
}

- (void)resize:(CGSize)size {
    _view->setViewport({0, 0, (uint32_t)size.width, (uint32_t)size.height});
    
    const double aspect = size.width / size.height;
    const double left   = -1.0 * aspect;
    const double right  =  1.0 * aspect;
    const double bottom = -1.0 * aspect;
    const double top    = 1.0 * aspect;
    const double near   =  0.1;
    const double far    =  10.0;
    _camera->setProjection(60, aspect,near, far, Camera::Fov::HORIZONTAL);

    // Position camera at origin looking towards negative Z
    _camera->lookAt({0, 0, 5}, {0, 0, 0}, {0, 1, 0});

}

- (void)drawInMTKView:(nonnull MTKView *)view {
    if (_renderer->beginFrame(_swapChain)) {
        
        auto& tcm = _engine->getTransformManager();
        tcm.create(_cube);
        auto i = tcm.getInstance(_cube);
        _rotationRadians += 0.01f;
//        math::mat4f tilt = math::mat4f::rotation(0.3f, math::float3{1, 0, 0});
        math::mat4f spin = math::mat4f::rotation(_rotationRadians, math::float3{0, 1, 0});
        math::mat4f model = spin;
        
        tcm.setTransform(i, model);

        _renderer->render(_view);
        _renderer->endFrame();
    }
}

- (void)dealloc {
    if (_engine) {
        _engine->destroyCameraComponent(_cameraEntity);
        EntityManager::get().destroy(_cameraEntity);
        
        if (_materialInstance) {
            _engine->destroy(_materialInstance);
        }
        if (_material) {
            _engine->destroy(_material);
        }
        
        if (_cubeIndexBuffer) {
            _engine->destroy(_cubeIndexBuffer);
        }
        if (_cubeVertexBuffer) {
            _engine->destroy(_cubeVertexBuffer);
        }
        
        if (_scene && _cube) {
            _scene->remove(_cube);
        }
        EntityManager::get().destroy(_cube);
        
        if (_scene && _light) {
            _scene->remove(_light);
        }
        EntityManager::get().destroy(_light);
        
        if (_scene && _light2) {
            _scene->remove(_light2);
        }
        EntityManager::get().destroy(_light2);
        
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
        
        Engine::destroy(&_engine);
    }
}

@end
