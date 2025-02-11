# ECS

A very simple and friendly entity-component system, loosely based on Unity3D's model of `GameObject`s and `MonoBehaviour`s.

If you prefer high-performance over simplicity, use an external Julia ECS package such as *Overseer.jl*.

## Overview

* A `World` is a list of `Entity` (plus accelerated lookup structures).
* An `Entity` is a list of `AbstractComponent`.
* A component has its own data and behavior, mostly in the form of a "TICK()" event that is invoked by the world.

You can update an entire world with `tick_world(world, delta_seconds::Float32)`.

To enable extra error-checking around your use of the ECS, enable the module's [debug asserts flag](Utilities.md#asserts) by executing `Bplus.ECS.bp_ecs_asserts_enabled() = true` while loading your game's code.

## Entity/component management

You can add and remove both entities and components:

* `add_entity(world)::Entity` and `remove_entity(world, entity)`
* `add_component(entity, T, constructor_args...; kw_constructor_args...)::T`
  * All the extra arguments get passed into the component's constructor (refer to `CONSTRUCT()` in the `@component` macro)
* `remove_component(entity, c::AbstractComponent)`

You can query the components on an `Entity` or entire `World`:

* `has_component(entity_or_world, T)::Bool`
* `get_component(entity, T)::Optional{T}`
  * Throws an error if there is more than one on the entity.
* `get_component(world, T)::Optional{Tuple{T, Entity}}`
  * Throws an error if there is more than one in the world.
  * Also returns the entity owning the component.
* `get_components(entity, T)::[iterator over T]`
  * Returns all components of the given type within the given entity.
* `get_components(world, T)::[iterator over Tuple{T, Entity}]`
  * Returns all components of the given type within the entire world, paired with their owning entities.
* `count_components(entity_or_world, T)::Int`
* `get_component_types(T)::Tuple{Vararg{Type}}`
  * Returns a list of the type T, its parent type, grandparent type, etc. up to but not including the root type `AbstractComponent`.

## `@component`

You can define component types with the `@component` macro. Components have a OOP structure to them; abstract parent components can add fields, "promises" (a.k.a. abstract functions) and "configurables" (a.k.a. virtual functions).

Refer to the `@component` doc-string for a very detailed explanation of the features and syntax.

### Internal interface

If you wish, you can go around `@component` and manually implement a component. Simply define a mutable struct inheriting from`AbstractComponent` (or a child of it), and implement the interface described in *ECS/interface.jl*.

## Component printing

By default, when printing a component defined with `@component`, fields that reference an `Entity` `World` or `AbstractComponent` are shortened for brevity.

You can customize how a specific field of your `@component` displays itself, in `print()`, by overloading `component_field_print(component, Val{:my_field}, field_value, io::IO)`.
