module Hasura.RQL.IR.Root
  ( RootField(..)
  , QueryDB(..)
  , MutationDB(..)
  , ActionQuery(..)
  , ActionMutation(..)
  , DBField(..)
  , QueryRootField
  , QueryDBRootField
  , QueryActionRootField
  , MutationRootField
  , MutationDBRootField
  , MutationActionRootField
  , SubscriptionRootField
  , QueryDBRoot(..)
  , MutationDBRoot(..)
  , traverseQueryDB
  , traverseActionQuery
  ) where

import           Hasura.Prelude

import qualified Data.Aeson.Ordered            as JO
import qualified Data.Kind                     as T

import qualified Hasura.RQL.IR.Delete          as IR
import qualified Hasura.RQL.IR.Insert          as IR
import qualified Hasura.RQL.IR.Select          as IR
import qualified Hasura.RQL.IR.Update          as IR
import qualified Hasura.RQL.Types.Action       as RQL
import qualified Hasura.RQL.Types.Backend      as RQL
import qualified Hasura.RQL.Types.Common       as RQL
import qualified Hasura.RQL.Types.RemoteSchema as RQL
import qualified Hasura.SQL.AnyBackend         as AB

import           Hasura.SQL.Backend

data DBField (field :: BackendType -> T.Type) (b :: BackendType)
  = DBField
  { _dfSourceName   :: !RQL.SourceName
  , _dfSourceConfig :: !(RQL.SourceConfig b)
  , _dfField        :: !(field b)
  }

data RootField db remote action raw where
  RFDB     :: db -> RootField db remote action raw
  RFRemote :: remote -> RootField db remote action raw
  RFAction :: action -> RootField db remote action raw
  RFRaw    :: raw    -> RootField db remote action raw

data QueryDB (b :: BackendType) v
  = QDBMultipleRows (IR.AnnSimpleSelG       b v)
  | QDBSingleRow    (IR.AnnSimpleSelG       b v)
  | QDBAggregation  (IR.AnnAggregateSelectG b v)
  | QDBConnection   (IR.ConnectionSelect    b v)
  deriving stock (Generic)

data MutationDB (b :: BackendType) v
  = MDBInsert (IR.AnnInsert b v)
  | MDBUpdate (IR.AnnUpdG   b v)
  | MDBDelete (IR.AnnDelG   b v)
  | MDBFunction RQL.JsonAggSelect (IR.AnnSimpleSelG b v)
  -- ^ This represents a VOLATILE function, and is AnnSimpleSelG for easy
  -- re-use of non-VOLATILE function tracking code.
  deriving stock (Generic)

data ActionQuery (b :: BackendType) v
  = AQQuery !(RQL.AnnActionExecution  b v)
  | AQAsync !(RQL.AnnActionAsyncQuery b v)

data ActionMutation (b :: BackendType) v
  = AMSync !(RQL.AnnActionExecution b v)
  | AMAsync !RQL.AnnActionMutationAsync

-- The `db` type argument of @RootField@ expects only one type argument, the
-- backend `b`, as not all types stored in a RootField will have a second
-- parameter like @QueryDB@ does: they all only have in common the fact that
-- they're parametric over the backend. To define @QueryRootField@ in terms of
-- @QueryDB@ (and likewise for mutations), we need a type-level function `b ->
-- QueryDB b (v b)`. Sadly, neither type synonyms nor type families may be
-- partially applied. Hence the need for @QueryDBRoot@ and @MutationDBRoot@.
newtype QueryDBRoot    v b = QDBR (QueryDB    b (v b))
newtype MutationDBRoot v b = MDBR (MutationDB b (v b))

type QueryDBRootField v = AB.AnyBackend (DBField (QueryDBRoot v))
type MutationDBRootField v = AB.AnyBackend (DBField (MutationDBRoot v))

type QueryActionRootField v =
  ActionQuery ('Postgres 'Vanilla) (v ('Postgres 'Vanilla))
type MutationActionRootField v =
  ActionMutation ('Postgres 'Vanilla) (v ('Postgres 'Vanilla))

type QueryRootField v =
  RootField (QueryDBRootField v) RQL.RemoteField (QueryActionRootField v) JO.Value
type MutationRootField v =
  RootField (MutationDBRootField v) RQL.RemoteField (MutationActionRootField v) JO.Value
type SubscriptionRootField v =
  RootField (QueryDBRootField v) Void Void Void

traverseQueryDB
  :: forall backend f a b
   . (Applicative f, RQL.Backend backend)
  => (a -> f b)
  -> QueryDB backend a
  -> f (QueryDB backend b)
traverseQueryDB f = \case
  QDBMultipleRows s -> QDBMultipleRows <$> IR.traverseAnnSimpleSelect    f s
  QDBSingleRow    s -> QDBSingleRow    <$> IR.traverseAnnSimpleSelect    f s
  QDBAggregation  s -> QDBAggregation  <$> IR.traverseAnnAggregateSelect f s
  QDBConnection   s -> QDBConnection   <$> IR.traverseConnectionSelect   f s

traverseActionQuery
  :: forall backend f a b
   . (Applicative f, RQL.Backend backend)
  => (a -> f b)
  -> ActionQuery backend a
  -> f (ActionQuery backend b)
traverseActionQuery f = \case
  AQQuery actionExecution -> AQQuery <$> RQL.traverseAnnActionExecution  f actionExecution
  AQAsync actionAsyncQ    -> AQAsync <$> RQL.traverseAnnActionAsyncQuery f actionAsyncQ
