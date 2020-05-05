module Language.PS.AST.Types where

-- | This module is somewhat inspired by `purescript-cst` types.
-- | I've tried to preserve constructor names to simplify
-- | further "copy and paste based development".

import Prelude

import Data.Either (Either)
import Data.Foldable (class Foldable, foldMap, foldlDefault, foldrDefault)
import Data.Functor.Mu (Mu)
import Data.Generic.Rep (class Generic)
import Data.Generic.Rep.Show (genericShow)
import Data.List (List)
import Data.Map (Map)
import Data.Map (unionWith) as Map
import Data.Maybe (Maybe(..))
import Data.Newtype (class Newtype)
import Data.Set (Set)
import Data.Set (fromFoldable, union) as Set
import Data.Traversable (class Traversable, sequence, traverseDefault)

-- | No need for imports list as they are collected from declarations
-- | during final codegen.
newtype Module = Module
  { declarations :: List Declaration
  , moduleName :: ModuleName
  }

newtype ModuleName = ModuleName String
derive instance newtypeModuleName :: Newtype ModuleName _
derive instance genericModuleName :: Generic ModuleName _
derive instance eqModuleName :: Eq ModuleName
derive instance ordModuleName :: Ord ModuleName
instance showModuleName :: Show ModuleName where
  show = genericShow

type QualifiedName a =
  { moduleName :: Maybe ModuleName
  , name :: a
  }

newtype TypeName = TypeName String
derive instance newtypeTypeName :: Newtype TypeName _
derive instance genericTypeName :: Generic TypeName _
derive instance eqTypeName :: Eq TypeName
derive instance ordTypeName :: Ord TypeName
instance showTypeName :: Show TypeName where
  show = genericShow

type QualifiedTypeName = QualifiedName TypeName

type Constraint ref
  = { className :: QualifiedName ClassName, params :: Array ref }

data TypeF ref
  = TypeApp ref (Array ref)
  | TypeArr ref ref
  | TypeArray ref
  | TypeBoolean
  | TypeConstructor QualifiedTypeName
  | TypeConstrained (Constraint ref) ref
  | TypeForall (Array Ident) ref
  | TypeNumber
  -- | TODO: How to handle this mutual recursion in a more
  -- | generic manner.
  | TypeRecord (RowF ref)
  | TypeRow (RowF ref)
  | TypeString
  | TypeVar Ident

type Type = Mu TypeF

derive instance genericPropType :: Generic (TypeF ref) _
instance showPropType :: Show ref => Show (TypeF ref) where
  show p = genericShow p

derive instance functorTypeF :: Functor TypeF
instance foldableTypeF :: Foldable TypeF where
  foldMap f (TypeApp l arguments) = f l <> foldMap f arguments
  foldMap f (TypeArr arg res) = f arg <> f res
  foldMap f (TypeArray t) = f t
  foldMap _ TypeBoolean = mempty
  foldMap f (TypeConstrained { className, params } t) =
    foldMap f params <> f t
  foldMap _ (TypeConstructor _) = mempty
  foldMap f (TypeRecord r) = foldMap f r
  foldMap f (TypeRow r) = foldMap f r
  foldMap _ TypeNumber = mempty
  foldMap f (TypeForall _ t) = f t
  foldMap _ TypeString = mempty
  foldMap _ (TypeVar _) = mempty

  foldr f t = foldrDefault f t
  foldl f t = foldlDefault f t

instance traversableTypeF :: Traversable TypeF where
  sequence (TypeApp l arguments) =
    TypeApp <$> l <*> sequence arguments
  sequence (TypeArr arg res) = TypeArr <$> arg <*> res
  sequence (TypeArray t) = TypeArray <$> t
  sequence TypeBoolean = pure TypeBoolean
  sequence (TypeConstrained { className, params } t) =
    TypeConstrained <<< { className, params: _ } <$> sequence params <*> t
  sequence (TypeConstructor t) = pure $ TypeConstructor t
  sequence (TypeForall v t) = TypeForall v <$> t
  sequence TypeNumber = pure $ TypeNumber
  sequence (TypeRecord ts) = TypeRecord <$> sequence ts
  sequence (TypeRow ts) = TypeRow <$> sequence ts
  sequence TypeString = pure $ TypeString
  sequence (TypeVar ident) = pure $ TypeVar ident

  traverse = traverseDefault

newtype RowF ref
  = Row
    { labels :: Map String ref
    -- | Currently we allow only type reference here
    -- | but we should provide full Type support in this place.
    , tail :: Maybe (Either Ident QualifiedTypeName)
    }
derive instance genericRowType :: Generic (RowF ref) _
derive instance newtypeRowF :: Newtype (RowF ref) _
instance showRowType :: Show ref => Show (RowF ref) where
  show p = genericShow p

derive instance functorRowF :: Functor RowF
derive instance eqRow :: Eq ref => Eq (RowF ref)

instance foldableRowF :: Foldable RowF where
  foldMap f (Row { labels }) = foldMap f labels
  foldr f t = foldrDefault f t
  foldl f t = foldlDefault f t

instance traversableRowF :: Traversable RowF where
  sequence (Row { labels, tail }) = Row <<< { labels: _, tail } <$> sequence labels
  traverse = traverseDefault

-- | I hope that this assymetry between `Row` and `Type`
-- | simplifies structure of most our algebras.
type Row = RowF Type

emptyRow :: Row
emptyRow = Row { labels: mempty, tail: Nothing }

type RowLabel = String

newtype Ident = Ident String
derive instance genericIdent :: Generic Ident _
derive instance eqIdent :: Eq Ident
derive instance ordIdent :: Ord Ident
instance showIdent :: Show Ident where
  show = genericShow

data ExprF ref
  = ExprApp ref ref
  | ExprArray (Array ref)
  | ExprBoolean Boolean
  | ExprIdent (QualifiedName Ident)
  | ExprNumber Number
  | ExprRecord (Map RowLabel ref)
  | ExprString String

derive instance functorExprF :: Functor ExprF

instance foldableExprF :: Foldable ExprF where
  foldMap f (ExprApp g a) = f g <> f a
  foldMap f (ExprArray arr) = foldMap f arr
  foldMap _ (ExprBoolean _) = mempty
  foldMap _ (ExprIdent _) = mempty
  foldMap _ (ExprNumber _) = mempty
  foldMap f (ExprRecord labels) = foldMap f labels
  foldMap _ (ExprString _) = mempty

  foldr f t = foldrDefault f t
  foldl f t = foldlDefault f t

instance traversableExprF :: Traversable ExprF where
  sequence (ExprApp g a) = ExprApp <$> g <*> a
  sequence (ExprArray arr) = ExprArray <$> sequence arr
  sequence (ExprBoolean b) = pure (ExprBoolean b)
  sequence (ExprIdent i) = pure (ExprIdent i)
  sequence (ExprNumber n) = pure (ExprNumber n)
  sequence (ExprRecord labels) = ExprRecord <$> sequence labels
  sequence (ExprString s) = pure (ExprString s)
  traverse = traverseDefault

type Expr = Mu ExprF

-- | Original CST type name doesn't contain a signature.
-- | Also the rest of the structure is radically simplified
-- | here to cover only current codegen cases.
type ValueBindingFields =
  { value ::
    { name :: Ident
    , binders :: Array Ident
    , expr :: Expr
    }
  , signature :: Maybe Type
  }

data DeclDataType = DeclDataTypeData | DeclDataTypeNewtype

data Declaration
  = DeclInstance
    { head ::
      { name :: Ident
      , className :: QualifiedName ClassName
      , types :: Array Type
      }
    , body :: Array ValueBindingFields
    }
  | DeclForeignValue { ident :: Ident, type :: Type }
  | DeclForeignData { typeName :: TypeName } -- , "kind" :: Maybe KindName }
  | DeclType { typeName :: TypeName, type :: Type, vars :: Array Ident }
  | DeclData { dataDeclType :: DeclDataType, typeName :: TypeName, vars :: Array Ident, constructors :: Array { name :: TypeName, types :: Array Type } }
  | DeclValue ValueBindingFields

newtype ClassName = ClassName String
derive instance newtypeClassName :: Newtype ClassName _
derive instance genericClassName :: Generic ClassName _
derive instance eqClassName :: Eq ClassName
derive instance ordClassName :: Ord ClassName
instance showClassName :: Show ClassName where
  show = genericShow

data Import
  = ImportValue Ident
  | ImportType TypeName
  | ImportClass ClassName
derive instance newtypeIdent :: Newtype Ident _
derive instance genericImport :: Generic Import _
derive instance eqImport :: Eq Import
derive instance ordImport :: Ord Import
instance showImport :: Show Import where
  show = genericShow

newtype ImportDecl = ImportDecl
  { moduleName :: ModuleName
  , names :: List Import
  }
derive instance newtypeImportDecl :: Newtype ImportDecl _
derive instance genericImportDecl :: Generic ImportDecl _
derive instance eqImportDecl :: Eq ImportDecl
derive instance ordImportDecl :: Ord ImportDecl
instance showImportDecl :: Show ImportDecl where
  show = genericShow

newtype Imports = Imports (Map ModuleName (Set Import))

instance semigroupImports :: Semigroup Imports where
  append (Imports i1) (Imports i2) = Imports $ Map.unionWith Set.union i1 i2

instance monoidImports :: Monoid Imports where
  mempty = Imports mempty

reservedNames :: Set String
reservedNames = Set.fromFoldable
  [ "ado" , "case" , "class" , "data"
  , "derive" , "do" , "else" , "false"
  , "forall" , "foreign" , "import" , "if"
  , "in" , "infix" , "infixl" , "infixr"
  , "instance" , "let" , "module" , "newtype"
  , "of" , "true" , "type" , "where"
  ]
