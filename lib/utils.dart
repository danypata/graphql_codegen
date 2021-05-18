import 'package:built_collection/built_collection.dart';
import 'package:gql/ast.dart';

class ContextFragment extends Context {
  final FragmentDefinitionNode fragment;
  final Name path;

  ContextFragment(
    Schema schema,
    FragmentDefinitionNode fragment,
    TypeDefinitionNode currentType,
    Map<String, Context> contexts, {
    Name? path,
  })  : this.fragment = fragment,
        this.path = path ?? Name.fromSegment(FragmentNameSegment(fragment)),
        super(
          schema: schema,
          currentType: currentType,
          contexts: contexts,
        );

  @override
  ContextFragment withNameAndType(
    NameSegment name,
    TypeDefinitionNode currentType, {
    FragmentDefinitionNode? inFragment,
    Name? possibleTypeOf,
  }) {
    final c = ContextFragment(
      schema,
      fragment,
      currentType,
      _contexts,
      path: path.withSegment(name),
    );
    _contexts[c.path.key] = c;
    return c;
  }
}

const _BUILT_IN_SCALARS = const DocumentNode(definitions: [
  ScalarTypeDefinitionNode(name: NameNode(value: 'Int')),
  ScalarTypeDefinitionNode(name: NameNode(value: 'String')),
  ScalarTypeDefinitionNode(name: NameNode(value: 'Float')),
  ScalarTypeDefinitionNode(name: NameNode(value: 'Boolean')),
  ScalarTypeDefinitionNode(name: NameNode(value: 'ID')),
]);

const _INTROSPECTION_FIELDS = const <FieldDefinitionNode>[
  FieldDefinitionNode(
    name: NameNode(value: "__typename"),
    type: NamedTypeNode(
      name: NameNode(value: "String"),
      isNonNull: true,
    ),
  ),
];

class Schema<TKey> {
  final BuiltMap<TKey, DocumentNode> entries;
  Iterable<DefinitionNode>? _cachedDefinitions;
  final String Function(TKey) lookupPath;

  Schema(
    this.entries,
    this.lookupPath,
  );

  Iterable<DefinitionNode> get definitions {
    final lCached = _cachedDefinitions;
    if (lCached != null) return lCached;
    final defs = [
      ...entries.values.expand((element) => element.definitions),
      ..._BUILT_IN_SCALARS.definitions,
    ];
    _cachedDefinitions = defs;
    return defs;
  }

  FragmentDefinitionNode? lookupFragment(NameNode name) {
    return definitions
        .whereType<FragmentDefinitionNode>()
        .map<FragmentDefinitionNode?>((e) => e)
        .firstWhere(
          (element) => element != null && element.name.value == name.value,
          orElse: () => null,
        );
  }

  String? lookupPathFromName(NameNode node) {
    for (final entry in entries.entries) {
      for (final definition in entry.value.definitions) {
        NameNode name;
        if (definition is FragmentDefinitionNode) {
          name = definition.name;
        } else if (definition is OperationDefinitionNode) {
          name = definition.name!;
        } else if (definition is EnumTypeDefinitionNode) {
          name = definition.name;
        } else {
          continue;
        }
        if (name.value == node.value) {
          return lookupPath(entry.key);
        }
      }
    }
    return null;
  }

  TypeDefinitionNode? lookupType(NameNode name) {
    return definitions
        .whereType<TypeDefinitionNode>()
        .map<TypeDefinitionNode?>((e) => e)
        .firstWhere(
          (element) => element != null && element.name.value == name.value,
          orElse: () => null,
        );
  }

  NameNode _operationTypeToDefaultClass(OperationType operationType) {
    switch (operationType) {
      case OperationType.mutation:
        return const NameNode(value: 'Mutation');
      case OperationType.subscription:
        return const NameNode(value: 'Subscription');
      case OperationType.query:
        return const NameNode(value: 'Query');
    }
  }

  TypeDefinitionNode? lookupOperationType(OperationType operationType) {
    final opNode = definitions
        .whereType<SchemaDefinitionNode>()
        .map<SchemaDefinitionNode?>((e) => e)
        .firstWhere((element) => element != null, orElse: () => null)
        ?.operationTypes
        .map<OperationTypeDefinitionNode?>((e) => e)
        .firstWhere(
          (element) => element != null && element.operation == operationType,
          orElse: () => null,
        );

    final typeName =
        opNode?.type.name ?? _operationTypeToDefaultClass(operationType);

    return lookupType(typeName);
  }

  TypeNode? lookupTypeNodeFromField(
    TypeDefinitionNode onType,
    FieldNode node,
  ) {
    List<FieldDefinitionNode> fields;
    if (onType is ObjectTypeDefinitionNode) {
      fields = onType.fields;
    } else if (onType is InterfaceTypeDefinitionNode) {
      fields = onType.fields;
    } else {
      return null;
    }
    final currentFieldDefinition = [...fields, ..._INTROSPECTION_FIELDS]
        .whereType<FieldDefinitionNode?>()
        .firstWhere(
          (element) => element != null && element.name.value == node.name.value,
          orElse: () => null,
        );
    return currentFieldDefinition?.type;
  }

  TypeDefinitionNode? lookupTypeDefinitionFromTypeNode(TypeNode node) {
    if (node is ListTypeNode) {
      return lookupTypeDefinitionFromTypeNode(node.type);
    }
    if (node is NamedTypeNode) {
      final type = lookupType(node.name);
      return type;
    }
    throw StateError("Invalid node type");
  }
}

class ContextProperty {
  final FieldNode field;
  final Name? path;
  final bool isEnum;

  ContextProperty(this.field, {this.path, this.isEnum = false});

  String get name => field.alias?.value ?? field.name.value;

  bool get isTypenameField => field.name.value == "__typename";
}

class TypedName {
  final Name name;
  final NameNode type;

  String get key => name.key;

  TypedName(this.name, this.type);
}

abstract class Context<TKey, TType extends TypeDefinitionNode> {
  Context({
    this.inFragment = null,
    required this.schema,
    Map<String, Context>? contexts,
    TType? currentType,
    this.possibleTypeOf,
  })  : _fragments = {},
        _possibleTypeNames = {},
        _properties = {},
        _currentType = currentType,
        _contexts = contexts ?? {};

  final Schema<TKey> schema;
  final Map<String, Context> _contexts;

  final TType? _currentType;

  final Name? possibleTypeOf;
  final Name? inFragment;

  final Map<String, Name> _fragments;
  final Map<String, TypedName> _possibleTypeNames;
  final Map<String, ContextProperty> _properties;

  TType get currentType {
    final lt = _currentType;
    if (lt != null) {
      return lt;
    }
    throw StateError("Missing current type");
  }

  Iterable<String> get fragmentKeys => _fragments.values.map((nm) => nm.key);

  Iterable<Name> get fragments => _fragments.values;

  ContextOperation<TKey>? get possibleTypeOfContext {
    final pt = possibleTypeOf;
    return pt == null ? null : _lookupContextOperation(pt);
  }

  ContextFragment withFragmentAndType(
    FragmentDefinitionNode node,
    TypeDefinitionNode type,
  ) {
    final c = ContextFragment(
      schema,
      node,
      type,
      _contexts,
    );
    _contexts[c.path.key] = c;
    return c;
  }

  Context withEnum(EnumTypeDefinitionNode type) {
    final c = ContextEnum(
      schema: schema,
      en: type,
    );
    _contexts[c.path.key] = c;
    return c;
  }

  ContextOperation withOperationAndType(
    OperationDefinitionNode node,
    TypeDefinitionNode type,
  ) {
    final c = ContextOperation(
      path: Name.fromSegment(OperationNameSegment(node)),
      currentType: type,
      schema: schema,
      contexts: _contexts,
    );
    _contexts[c.path.key] = c;
    return c;
  }

  ContextOperation<TKey>? _lookupContextOperation(Name path) {
    final c = _contexts[path.key];
    if (c == null) return null;
    return c is ContextOperation<TKey> ? c : null;
  }

  void addFragment(Name fragment) {
    _fragments[fragment.key] = fragment;
  }

  void addPossibleTypeName(Context c) {
    _possibleTypeNames[c.path.key] = TypedName(c.path, c.currentType.name);
  }

  void addProperty(ContextProperty property) {
    if (_properties[property.name] != null) {
      return;
    }
    _properties[property.name] = property;
  }

  Iterable<ContextProperty> get properties => _properties.values;

  Iterable<ContextProperty> get publicProperties =>
      _properties.values.where((element) => !element.name.startsWith("_"));

  Name get path => throw StateError("Path not available");

  Context withNameAndType(
    NameSegment name,
    TypeDefinitionNode currentType, {
    FragmentDefinitionNode? inFragment,
    Name? possibleTypeOf,
  }) {
    throw new StateError('withNameAndType not supported');
  }
}

class ContextRoot<TKey> extends Context<TKey, TypeDefinitionNode> {
  final key;

  ContextRoot({
    required Schema<TKey> schema,
    required this.key,
  }) : super(
          schema: schema,
          contexts: {},
        );
  Iterable<ContextOperation> get contextsOperations =>
      _contexts.values.whereType<ContextOperation>();

  Iterable<ContextFragment> get contextFragments =>
      _contexts.values.whereType<ContextFragment>();

  Iterable<ContextEnum> get contextEnums =>
      _contexts.values.whereType<ContextEnum>();

  Iterable<NameNode> get dependencies => Set.from(
        [
          ...contextsOperations.expand<NameNode>(
            (e) => [
              ...e.fragments.map((e) => e.baseNameSegment.name),
              ...e.properties
                  .map<NameNode?>((e) => e.path?.baseNameSegment.name)
                  .whereType<NameNode>(),
            ],
          ),
        ],
      );
}

class ContextEnum<TKey> extends Context<TKey, EnumTypeDefinitionNode> {
  final Name path;
  ContextEnum({
    required Schema<TKey> schema,
    required EnumTypeDefinitionNode en,
  })   : path = Name.fromSegment(EnumNameSegment(en)),
        super(
          schema: schema,
          currentType: en,
        );
}

class ContextOperation<TKey> extends Context<TKey, TypeDefinitionNode> {
  final Name path;
  ContextOperation({
    required Name path,
    required Schema<TKey> schema,
    required Map<String, Context> contexts,
    required TypeDefinitionNode currentType,
    Name? possibleTypeOf,
    Name? inFragment,
  })  : this.path = path,
        super(
          schema: schema,
          contexts: contexts,
          currentType: currentType,
          possibleTypeOf: possibleTypeOf,
          inFragment: inFragment,
        );

  ContextOperation withNameAndType(
    NameSegment name,
    TypeDefinitionNode currentType, {
    FragmentDefinitionNode? inFragment,
    Name? possibleTypeOf,
  }) {
    final path = this.path.withSegment(name);
    final existingContext = _lookupContextOperation(path);
    if (existingContext != null) return existingContext;
    final currentInFragment = this.inFragment;
    final newInFragment = inFragment != null
        ? Name.fromSegment(FragmentNameSegment(inFragment))
        : (currentInFragment == null
            ? null
            : currentInFragment.withSegment(name));
    final c = ContextOperation(
      path: path,
      schema: schema,
      contexts: _contexts,
      currentType: currentType,
      possibleTypeOf: possibleTypeOf,
      inFragment: newInFragment,
    );
    _contexts[c.path.key] = c;
    return c;
  }

  ContextProperty? get typenameProperty =>
      properties.whereType<ContextProperty?>().firstWhere(
            (element) => element?.isTypenameField == true,
            orElse: () => null,
          );

  Iterable<TypedName> get possibleTypes => _possibleTypeNames.values;
}

class Name {
  final BuiltList<NameSegment> segments;
  final NameSegment baseNameSegment;

  Name(this.segments, this.baseNameSegment);

  factory Name.fromSegment(NameSegment segment) => Name(
        BuiltList.of([segment]),
        segment,
      );

  String get key => segments.map((e) => e.key).join(r"$");

  Name withSegment(NameSegment segment) => Name(
        (segments.toBuilder()..add(segment)).build(),
        baseNameSegment,
      );
}

abstract class NameSegment {
  final NameNode name;

  NameSegment(this.name);

  String get key;
}

class EnumNameSegment extends NameSegment {
  EnumNameSegment(EnumTypeDefinitionNode tpe) : super(tpe.name);

  @override
  String get key => "Enum${name.value}";
}

class FieldNameSegment extends NameSegment {
  FieldNameSegment(FieldNode name) : super(name.alias ?? name.name);

  @override
  String get key => "f${name.value}";
}

class TypeNameSegment extends NameSegment {
  TypeNameSegment(TypeConditionNode typeCondition)
      : super(typeCondition.on.name);

  @override
  String get key => "t${name.value}";
}

class OperationNameSegment extends NameSegment {
  final OperationDefinitionNode node;
  OperationNameSegment(OperationDefinitionNode name)
      : node = name,
        super(name.name!);

  @override
  String get key {
    switch (node.type) {
      case OperationType.mutation:
        return "Mutation${name.value}";
      case OperationType.query:
        return "Query${name.value}";
      case OperationType.subscription:
        return "Subscription${name.value}";
    }
  }
}

class FragmentNameSegment extends NameSegment {
  FragmentNameSegment(FragmentDefinitionNode node) : super(node.name);

  @override
  String get key => "Fragment${name.value}";
}