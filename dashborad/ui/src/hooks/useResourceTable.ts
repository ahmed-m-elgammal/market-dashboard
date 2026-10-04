/**
 * useTable, adapted to Ant Design's Table.
 *
 * WHY THIS EXISTS
 *   @refinedev/core's useTable returns { tableQuery, current, pageSize,
 *   setCurrent, setPageSize, sorters, setSorters }. It does NOT return
 *   `tableProps` — that was removed, and the types and the runtime both agree on
 *   its absence, so every list screen would otherwise repeat the same wiring of
 *   five pieces of state into AntD's Table props.
 *
 *   The pieces have to be joined by hand and the joins are easy to get subtly
 *   wrong:
 *
 *     - AntD's onChange fires for pagination AND sorting, so a single handler
 *       has to tell them apart or paging resets the sort.
 *     - Page size and current are coupled: switching from 10 to 50 rows while on
 *       page 7 must land on a page that exists. setPageSize does not clamp
 *       `current`, so it is clamped here.
 *     - AntD's sorter is a single object-or-array; Refine wants a CrudSort[].
 *
 *   Doing that once, here, is the difference between three screens that behave
 *   identically and three that drift.
 */
import { useCallback, useMemo } from 'react';
import { useTable } from '@refinedev/core';
import type {
  BaseRecord,
  CrudSort,
  HttpError,
  Pagination,
  useTableProps,
} from '@refinedev/core';
import type { TablePaginationConfig } from 'antd';

export interface ResourceTableOptions<T extends BaseRecord>
  extends Omit<useTableProps<T, HttpError, T>, 'sorters'> {
  /** Server-side sorting. The demo provider sorts in memory; the live provider
   *  will pass the field through to admin-api. */
  sorters?: useTableProps<T, HttpError, T>['sorters'];
}

export interface ResourceTable<T extends BaseRecord> {
  /** Rows for the current page. Empty rather than undefined while loading, so a
   *  Table never has to guard against a missing array. */
  data: T[];
  total: number;
  isLoading: boolean;
  error: HttpError | null;
  refetch: () => Promise<unknown>;
  /** Spread onto <Table>. */
  tableProps: {
    dataSource: T[];
    loading: boolean;
    pagination: TablePaginationConfig;
    onChange: (
      pagination: TablePaginationConfig,
      filters: unknown,
      sorter: unknown,
    ) => void;
  };
  /** AntD `sortOrder` for a column, so a column can show its sort arrow. */
  sortOrderFor: (field: string) => 'ascend' | 'descend' | null;
}

export function useResourceTable<T extends BaseRecord>(
  options: ResourceTableOptions<T>,
): ResourceTable<T> {
  const { tableQuery, current, pageSize, setCurrent, setPageSize, sorters, setSorters } =
    useTable<T, HttpError, T>(options as useTableProps<T, HttpError, T>);

  const data = useMemo(() => tableQuery.data?.data ?? [], [tableQuery.data]);
  const total = tableQuery.data?.total ?? 0;

  const handleChange = useCallback(
    (
      nextPagination: TablePaginationConfig,
      _filters: unknown,
      sorter: unknown,
    ) => {
      // AntD hands back the *whole* pagination object on every change, so each
      // field is compared rather than assigned: writing back an unchanged value
      // would reset an in-flight query.
      const nextSize = nextPagination.pageSize ?? pageSize;
      if (nextSize !== pageSize) {
        setPageSize(nextSize);
        // Page 7 of 10-rows-per-page no longer exists at 50 rows per page.
        // setPageSize does not clamp current, so the reset is explicit.
        setCurrent(1);
      } else {
        setCurrent(nextPagination.current ?? 1);
      }

      // A single click on a sortable header gives an object; multi-sort gives an
      // array. Refine only understands the array form.
      const list = Array.isArray(sorter) ? sorter : [sorter];
      const crud: CrudSort[] = list
        .filter((s): s is { field?: string | number; order?: string | null } =>
          Boolean(s && typeof s === 'object' && 'order' in s),
        )
        .map((s) => ({
          field: String(s.field ?? ''),
          order: s.order === 'ascend' ? 'asc' : s.order === 'descend' ? 'desc' : 'asc',
        }));
      setSorters(crud);
    },
    [pageSize, setCurrent, setPageSize, setSorters],
  );

  const pagination: TablePaginationConfig = useMemo(
    () => ({
      current,
      pageSize,
      total,
      showSizeChanger: true,
      onChange: (page, size) => handleChange({ current: page, pageSize: size }, null, []),
    }),
    [current, pageSize, total, handleChange],
  );

  return {
    data,
    total,
    isLoading: tableQuery.isLoading,
    error: tableQuery.error,
    refetch: tableQuery.refetch,
    tableProps: {
      dataSource: data,
      loading: tableQuery.isLoading,
      pagination,
      onChange: handleChange,
    },
    // Reads the sorter state useTable hands back rather than react-query's
    // query meta, which is not part of the public result type.
    sortOrderFor: (field: string) => {
      const match = sorters.find((s) => s.field === field);
      if (match?.order === 'asc') return 'ascend';
      if (match?.order === 'desc') return 'descend';
      return null;
    },
  };
}

/** Re-exported so pages can type a query result without importing @refinedev. */
export type { Pagination };