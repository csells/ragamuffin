import 'package:sqlite3/sqlite3.dart';

/// A typed query builder for SQLite operations
class TypedQuery<T> {
  /// Creates a typed query with SQL, parameters, and deserializer function
  const TypedQuery(this.sql, this.params, this.deserializer);

  /// The SQL query string
  final String sql;
  
  /// The query parameters
  final List<Object?> params;
  
  /// Function to deserialize database rows to type T
  final T Function(Map<String, Object?>) deserializer;
}

/// Extension on Database to add type-safe query methods
extension TypedDatabase on Database {
  /// Execute a typed SELECT query that returns multiple results
  List<T> selectTyped<T>(TypedQuery<T> query) {
    final resultSet = select(query.sql, query.params);
    return resultSet.map(query.deserializer).toList();
  }

  /// Execute a typed SELECT query that returns a single result or null
  T? selectSingleTyped<T>(TypedQuery<T> query) {
    final results = selectTyped(query);
    return results.isEmpty ? null : results.first;
  }

  /// Execute a typed INSERT query and return the row ID
  int insertTyped(String sql, List<Object?> params) {
    execute(sql, params);
    return lastInsertRowId;
  }

  /// Execute a typed UPDATE or DELETE query and return affected rows
  int executeTyped(String sql, List<Object?> params) {
    execute(sql, params);
    return updatedRows;
  }
}

/// Result wrapper for operations that might fail
sealed class DatabaseResult<T> {
  /// Creates a database result
  const DatabaseResult();
}

/// Successful operation result
class Success<T> extends DatabaseResult<T> {
  /// Creates a success result with data
  const Success(this.data);
  
  /// The result data
  final T data;
}

/// Operation failed because resource was not found
class NotFound<T> extends DatabaseResult<T> {
  /// Creates a not found result
  const NotFound();
}

/// Operation failed with an error
class DatabaseError<T> extends DatabaseResult<T> {
  /// Creates an error result with message
  const DatabaseError(this.message);
  
  /// The error message
  final String message;
}
