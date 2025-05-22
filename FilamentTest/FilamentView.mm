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

#include <filameshio/MeshReader.h>
#include <filament/Texture.h>
#include <filament/TextureSampler.h>
#include <filament/LightManager.h>


#include <utils/Entity.h>
#include <utils/EntityManager.h>

#include "FilamentView.h"
#import <MetalKit/MTKView.h>

using namespace filamesh;
using namespace filament;
using namespace utils;

@interface FilamentView() <MTKViewDelegate>
@property (nonatomic, strong) CADisplayLink *displayLink;
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
    
    Texture* _whiteTexture;
    MTKView* _mtkView;
    
    bool _initialized;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    _initialized = false;

    // Create the Metal view first
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    _mtkView = [[MTKView alloc] initWithFrame: self.view.bounds device:device];
    _mtkView.delegate = self;
    _mtkView.preferredFramesPerSecond = 60;
    _mtkView.enableSetNeedsDisplay = YES;
    [self.view addSubview:_mtkView];

    _mtkView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [_mtkView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_mtkView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_mtkView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_mtkView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
    ]];

    // Now initialize Filament
    [self initFilament];
}

- (void)initFilament {
    // Create engine with the Metal backend
    _engine = Engine::create(Engine::Backend::METAL);
    if (!_engine) {
        NSLog(@"❌ Failed to create Filament engine");
        return;
    }

    // Create the SwapChain from the MTKView's layer
    _swapChain = _engine->createSwapChain((__bridge void*) _mtkView.layer);
    if (!_swapChain) {
        NSLog(@"❌ Failed to create SwapChain");
        return;
    }

    // Create renderer
    _renderer = _engine->createRenderer();
    if (!_renderer) {
        NSLog(@"❌ Failed to create Renderer");
        return;
    }

    // Create view
    _view = _engine->createView();
    if (!_view) {
        NSLog(@"❌ Failed to create View");
        return;
    }

    // Create scene
    _scene = _engine->createScene();
    if (!_scene) {
        NSLog(@"❌ Failed to create Scene");
        return;
    }

    // Create camera entity
    _cameraEntity = EntityManager::get().create();
    _camera = _engine->createCamera(_cameraEntity);
    if (!_camera) {
        NSLog(@"❌ Failed to create Camera");
        return;
    }

    _renderer->setClearOptions({ .clearColor = {0.2f, 0.4f, 0.7f, 1.0f}, .clear = true });

    _view->setScene(_scene);
    _view->setCamera(_camera);
    [self resize:_mtkView.drawableSize];

    // Load material
    NSString *materialPath = [[NSBundle mainBundle] pathForResource:@"ball" ofType:@"filamat"];
    if (!materialPath) {
        NSLog(@"❌ Cannot find ball.filamat in bundle");
        return;
    }
    
    NSData *materialData = [NSData dataWithContentsOfFile:materialPath];
    if (!materialData) {
        NSLog(@"❌ Failed to load ball.filamat");
        return;
    }

    _material = Material::Builder()
        .package(materialData.bytes, materialData.length)
        .build(*_engine);
    
    if (!_material) {
        NSLog(@"❌ Failed to build material");
        return;
    }
    
    _materialInstance = _material->createInstance();
    if (!_materialInstance) {
        NSLog(@"❌ Failed to create material instance");
        return;
    }

    // Create a 1x1 white texture for baseColor
    uint8_t whitePixel[4] = {255, 255, 255, 255};
    _whiteTexture = Texture::Builder()
        .width(1).height(1).levels(1)
        .sampler(Texture::Sampler::SAMPLER_2D)
        .format(Texture::InternalFormat::RGBA8)
        .build(*_engine);
        
    if (!_whiteTexture) {
        NSLog(@"❌ Failed to create white texture");
        return;
    }
    
    Texture::PixelBufferDescriptor buffer(
        whitePixel, 4, Texture::Format::RGBA, Texture::Type::UBYTE,
        [](void*, size_t, void*) {}, nullptr
    );
    _whiteTexture->setImage(*_engine, 0, std::move(buffer));

    TextureSampler sampler(TextureSampler::MinFilter::LINEAR, TextureSampler::MagFilter::LINEAR);
    _materialInstance->setParameter("baseColor", _whiteTexture, sampler);

    // Load filamesh
    NSString *meshPath = [[NSBundle mainBundle] pathForResource:@"ball" ofType:@"filamesh"];
    if (!meshPath) {
        NSLog(@"❌ Cannot find ball.filamesh in bundle");
        return;
    }
    
    NSData *meshData = [NSData dataWithContentsOfFile:meshPath];
    if (!meshData) {
        NSLog(@"❌ Failed to load ball.filamesh");
        return;
    }

    // Create a copy of the mesh data to ensure it stays valid during loading
    void* meshDataCopy = malloc(meshData.length);
    memcpy(meshDataCopy, meshData.bytes, meshData.length);
    
    // Using a destructor that frees the memory when filament is done with it
    auto meshDataDestructor = [](void* buffer, size_t size, void* user) {
        free(buffer);
    };
    
    MeshReader::Mesh mesh = MeshReader::loadMeshFromBuffer(
        _engine,
        meshDataCopy,
        meshDataDestructor,
        nullptr,
        _materialInstance
    );

    _cubeVertexBuffer = mesh.vertexBuffer;
    _cubeIndexBuffer = mesh.indexBuffer;
    _cube = mesh.renderable;

    if (!_cube) {
        NSLog(@"❌ Failed to create mesh renderable entity");
        return;
    }

    // Check if transform component exists
    auto& tcm = _engine->getTransformManager();
    if (!tcm.hasComponent(_cube)) {
        NSLog(@"❌ Renderable entity doesn't have transform component");
        EntityManager::get().destroy(_cube);
        return;
    }

    // Position the ball in front of the camera and scale it
    // The scale factor of 2.0 will make the cube twice as large in each dimension
    math::float3 position{0, 0, 0};
    math::float3 scale{10.0f, 10.0f, 10.0f}; // Scale by 2x in each dimension

    math::mat4f translation = math::mat4f::translation(position);
    math::mat4f scaling = math::mat4f::scaling(scale);
    math::mat4f transform = translation * scaling; // Apply scaling after translation

    tcm.setTransform(tcm.getInstance(_cube), transform);

    _scene->addEntity(_cube);
    // Add directional light
    Entity light = EntityManager::get().create();
    LightManager::Builder(LightManager::Type::SUN)
        .color(math::float3{1.0f, 1.0f, 1.0f})
        .intensity(100000.0f)
        .direction(math::float3{0.0f, -1.0f, -1.0f})
        .castShadows(false)
        .build(*_engine, light);

    _scene->addEntity(light);
    
    _initialized = true;
    NSLog(@"✅ Filament initialization complete");
}

- (void)mtkView:(nonnull MTKView*)view drawableSizeWillChange:(CGSize)size {
    [self resize:size];
}

- (void)resize:(CGSize)size {
    if (!_view || !_camera || !_engine) return;
    
    _view->setViewport({0, 0, (uint32_t) size.width, (uint32_t) size.height});

    const double aspect = size.width / size.height;
    
    // Switch to perspective projection for better 3D visualization
    const double fov = 45.0 * M_PI / 180.0; // 45 degrees field of view in radians
    const double near = 0.1;
    const double far = 100.0;
    
    _camera->setProjection(Camera::Projection::PERSPECTIVE,
                          -aspect * std::tan(fov / 2),  // left
                          aspect * std::tan(fov / 2),   // right
                          -std::tan(fov / 2),           // bottom
                          std::tan(fov / 2),            // top
                          near, far);
    
    // Position camera to look at the center
    auto& tcm = _engine->getTransformManager();
    if (tcm.hasComponent(_cameraEntity)) {
        tcm.setTransform(
            tcm.getInstance(_cameraEntity),
            math::mat4f::translation(math::float3{0, 0, 5}) *
            math::mat4f::lookAt(math::float3{0, 0, 5}, math::float3{0, 0, 0}, math::float3{0, 1, 0})
        );
    }
}

- (void)drawInMTKView:(nonnull MTKView*)view {
    if (!_initialized || !_renderer || !_swapChain || !_view) return;
    
    if (_renderer->beginFrame(_swapChain)) {
        // Render the scene
        _renderer->render(_view);
        _renderer->endFrame();
    }
}

- (void)dealloc {
    if (_engine) {
        // Destroy entities first
        if (_camera) {
            _engine->destroyCameraComponent(_cameraEntity);
            EntityManager::get().destroy(_cameraEntity);
        }

        // Remove entities from scene
        if (_scene) {
            if (_cube) {
                _scene->remove(_cube);
                EntityManager::get().destroy(_cube);
            }
        }

        // Destroy material instance before material
        if (_materialInstance) {
            _engine->destroy(_materialInstance);
            _materialInstance = nullptr;
        }
        
        if (_material) {
            _engine->destroy(_material);
            _material = nullptr;
        }

        // Destroy white texture
        if (_whiteTexture) {
            _engine->destroy(_whiteTexture);
            _whiteTexture = nullptr;
        }

        // Clean up geometry
        if (_cubeIndexBuffer) {
            _engine->destroy(_cubeIndexBuffer);
            _cubeIndexBuffer = nullptr;
        }
        
        if (_cubeVertexBuffer) {
            _engine->destroy(_cubeVertexBuffer);
            _cubeVertexBuffer = nullptr;
        }

        // Destroy view, scene, renderer, swapchain
        if (_view) {
            _engine->destroy(_view);
            _view = nullptr;
        }
        
        if (_scene) {
            _engine->destroy(_scene);
            _scene = nullptr;
        }
        
        if (_renderer) {
            _engine->destroy(_renderer);
            _renderer = nullptr;
        }
        
        if (_swapChain) {
            _engine->destroy(_swapChain);
            _swapChain = nullptr;
        }

        // Finally destroy the engine
        Engine::destroy(&_engine);
        _engine = nullptr;
    }
}

@end
