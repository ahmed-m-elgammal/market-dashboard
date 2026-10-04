/**
 * Item mutations, in one place.
 *
 * WHY A HOOK RATHER THAN THREE useUpdate CALLS IN THE PAGE
 *   The three actions here are the ones an operator can get wrong, and they are
 *   wrong in ways that are invisible afterwards. Centralising them means the
 *   confirm text, the refetch and the success message cannot drift apart between
 *   the items table and the item screen — and there is exactly one place to read
 *   to understand what "delete" actually does.
 *
 * THE THREE ACTIONS ARE NOT THE SAME THING
 *
 *   markUnavailable  sets is_available = false. The merchant's toggle. Reversible
 *                    with one click, no confirmation, because nothing is lost.
 *
 *   softDelete       sets deleted_at = now. An administrative removal.
 *
 *   restore          clears deleted_at. Undoes the above.
 *
 * WHY DELETE IS SOFT, AND WHY THAT IS NOT A DETAIL
 *   Migration 110 records the original bug: order_items.item_id used to be
 *   ON DELETE CASCADE, so a hard DELETE of an item erased every order line that
 *   referenced it while the orders row survived still claiming its total. Revenue
 *   became unreconcilable and the item could not be brought back. The migration
 *   changed the FK to SET NULL and added deleted_at precisely so a dashboard
 *   Delete button could exist without being dangerous.
 *
 *   So `deleteOne` here maps to a soft delete, the confirmation says the item is
 *   kept rather than erased, and restore is offered in the same place delete is.
 *   A UI that says "this cannot be undone" for a reversible action trains an
 *   operator to dismiss confirmations reflexively — which is how they will
 *   dismiss the one confirmation that matters.
 */
import { useCallback } from 'react';
import { App, Modal } from 'antd';
import { useDelete, useUpdate } from '@refinedev/core';
import type { Item } from '../constants';
import { useLang } from '../i18n/LangProvider';
import { t } from '../i18n/strings';

/** The subset of an item these actions need. */
type ActionableItem = Pick<Item, 'id' | 'name_en' | 'name_ar' | 'deleted_at' | 'is_available'>;

export interface ItemActions {
  /** Toggle the merchant-facing availability flag. */
  toggleAvailability: (id: string, next: boolean) => void;
  /** Soft delete, behind a confirmation that states the item is retained. */
  softDelete: (item: ActionableItem) => void;
  /** Clear deleted_at. */
  restore: (id: string) => void;
}

export function useItemActions(): ItemActions {
  const { lang } = useLang();
  const { message } = App.useApp();
  const { mutate: update } = useUpdate();
  const { mutate: remove } = useDelete();

  const handleError = useCallback(
    (error: unknown) => {
      const e = error as { messageAr?: string; message?: string };
      message.error(
        (lang === 'ar' ? e.messageAr : e.message) ?? t('unexpectedError', lang),
      );
    },
    [lang, message],
  );

  const toggleAvailability = useCallback(
    (id: string, next: boolean) => {
      update(
        { resource: 'items', id, values: { is_available: next } },
        {
          // The list is refetched rather than patched in place: a soft delete or
          // a create elsewhere would leave an optimistic row list inconsistent
          // with the counts in the card header, and a stale count on a menu
          // screen is worse than a brief spinner.
          onSuccess: () =>
            message.success(
              t(next ? 'itemMarkedAvailable' : 'itemMarkedUnavailable', lang),
            ),
          onError: handleError,
        },
      );
    },
    [update, message, lang, handleError],
  );

  const softDelete = useCallback(
    (item: ActionableItem) => {
      Modal.confirm({
        title: t('deleteItemConfirmTitle', lang),
        content: t('deleteItemConfirmBody', lang),
        okText: t('deleteItem', lang),
        okButtonProps: { danger: true },
        cancelText: t('cancel', lang),
        onOk: () =>
          new Promise<void>((resolve, reject) => {
            remove(
              { resource: 'items', id: item.id },
              {
                onSuccess: () => {
                  message.success(t('itemDeleted', lang));
                  resolve();
                },
                onError: (error: unknown) => {
                  handleError(error);
                  reject(error);
                },
              },
            );
          }),
      });
    },
    [remove, message, lang, handleError],
  );

  const restore = useCallback(
    (id: string) => {
      update(
        { resource: 'items', id, values: { deleted_at: null } },
        {
          onSuccess: () => message.success(t('itemRestored', lang)),
          onError: handleError,
        },
      );
    },
    [update, message, lang, handleError],
  );

  return { toggleAvailability, softDelete, restore };
}